# Solution Walkthrough

This walkthrough follows the task from top to bottom and ends each section with a check. The `DestinationRule` is already correct, so the whole lab is about one `VirtualService`. Items 1 and 2 describe the new object, so you write it once and check it in two steps. Items 3 and 4 prove that the split reaches the proxy and works. Items 5 to 7 prove that you changed nothing else.

---

## Start: Read The Starting State

The task says that the `VirtualService` sends every request to `v1`. Look at it, and count where the requests go today:

```sh
kubectl -n starfleet get virtualservice scout -o jsonpath='{.spec}{"\n"}'
for i in $(seq 1 20); do
  kubectl -n starfleet exec deploy/shuttle -- curl -s http://scout:9080/reviews/0 | grep -o 'scout-v[0-9]'
done | sort | uniq -c
```

```text
{"hosts":["scout"],"http":[{"route":[{"destination":{"host":"scout","subset":"v1"}}]}]}
  20 scout-v1
```

The route has one destination and no weight. Every request goes to `v1`. The `v2` and `v3` pods run, but no route sends them a request.

The task says that the `DestinationRule` must stay unchanged, and so must the workloads. Save their identity now. Items 6 and 7 compare against it:

```sh
kubectl -n starfleet get destinationrule scout -o jsonpath='generation={.metadata.generation} uid={.metadata.uid}{"\n"}'
kubectl -n starfleet get destinationrule scout -o jsonpath='{range .spec.subsets[*]}{.name}={.labels.version}{"\n"}{end}'
kubectl -n starfleet get deploy -o custom-columns=NAME:.metadata.name,REPLICAS:.spec.replicas,UID:.metadata.uid
kubectl -n starfleet get svc -o custom-columns=NAME:.metadata.name,PORT:.spec.ports[0].port,SELECTOR:.spec.selector
```

```text
generation=1 uid=558fb5c2-d35d-4141-8f76-ad745d3762ab
v1=v1
v2=v2
v3=v3
NAME        REPLICAS   UID
bridge-v1   1          d7709143-621c-4407-9644-ecdac2d0c469
cargo-v1    1          f6140560-ae4d-4b3f-a8ca-3fe4a2e2d29e
navcom-v1   1          a1d3d77c-9836-4834-b209-2497bfb248b3
scout-v1    1          b008278d-5994-4f76-9cab-81ee6aef0bf8
scout-v2    1          3a323752-3cd9-4b82-b3bf-ce40f0aee927
scout-v3    1          9b12e9a5-fa1b-4fa3-bccd-89f43e300f6d
shuttle     1          cf0f18a9-6da6-467b-9036-54c84f5cdbbd
NAME     PORT   SELECTOR
bridge   9080   map[app:bridge]
cargo    9080   map[app:cargo]
navcom   9080   map[app:navcom]
scout    9080   map[app:scout]
```

---

## Items 1 And 2: Write One Rule With Three Weighted Destinations

> **Task item 1:** The `VirtualService` named `scout` in `starfleet` has **exactly one** `http` rule, with **no** `match`.
>
> **Task item 2:** That rule's route has three destinations on `scout`: subset **`v1` with weight 60**, subset **`v2` with weight 30** and subset **`v3` with weight 10**.

A `VirtualService` tells the sidecar proxies where to send requests for a host. A sidecar proxy is the Envoy container that Istio adds to each pod. A subset is a named group of pods that the `DestinationRule` defines. Put all three destinations in the same route list of one rule, and give each one a `weight` next to its `destination`, not inside it. A rule without `match` takes every request.

Edit `virtualservice-scout.yaml`, or save this as `virtualservice-scout.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: scout
  namespace: starfleet
spec:
  hosts:
  - scout
  http:
  - route:
    - destination:
        host: scout
        subset: v1
      weight: 60
    - destination:
        host: scout
        subset: v2
      weight: 30
    - destination:
        host: scout
        subset: v3
      weight: 10
```

Apply it:

```sh
kubectl apply -f virtualservice-scout.yaml
```

```text
virtualservice.networking.istio.io/scout configured
```

The object keeps its name, so `kubectl apply` replaces the old `VirtualService`. You do not delete anything first.

Check item 1. Print the whole `http` list. It must hold one rule and no `match`:

```sh
kubectl -n starfleet get virtualservice scout -o jsonpath='{.spec.http}{"\n"}'
```

```text
[{"route":[{"destination":{"host":"scout","subset":"v1"},"weight":60},{"destination":{"host":"scout","subset":"v2"},"weight":30},{"destination":{"host":"scout","subset":"v3"},"weight":10}]}]
```

The list has exactly one rule, and the rule has no `match` field. Check item 2. Print each destination with its weight:

```sh
kubectl -n starfleet get virtualservice scout \
  -o jsonpath='{range .spec.http[0].route[*]}{.destination.host}{" "}{.destination.subset}{" weight="}{.weight}{"\n"}{end}'
```

```text
scout v1 weight=60
scout v2 weight=30
scout v3 weight=10
```

The three destinations are on the host `scout`, with the weights 60, 30 and 10.

---

## Item 3: The Proxy Holds The Weights

> **Task item 3:** The `shuttle` pod's sidecar proxy holds those three weights for the `scout` route on port `9080`.

`istiod`, the Istio control plane, sends the new route to every sidecar proxy. Ask the proxy of `shuttle` for the weights it holds:

```sh
istioctl proxy-config routes deploy/shuttle -n starfleet --name 9080 -o json \
  | grep -A16 weightedClusters | grep -E '"name"|"weight"'
```

```text
                                        "name": "outbound|9080|v1|scout.starfleet.svc.cluster.local",
                                        "weight": 60
                                        "name": "outbound|9080|v2|scout.starfleet.svc.cluster.local",
                                        "weight": 30
                                        "name": "outbound|9080|v3|scout.starfleet.svc.cluster.local",
                                        "weight": 10
```

There is one Envoy cluster, a named destination, for each subset, and each has the weight that you wrote. If the output is empty, the route has not arrived yet. Wait a few seconds and run the command again.

---

## Item 4: Every Version Answers In Its Share

> **Task item 4:** Out of 200 requests sent to `http://scout:9080/reviews/0`, every version answers in roughly its share. The grader accepts 90–150 for `v1`, 36–84 for `v2` and 6–40 for `v3`.

The proxy makes a separate random pick for each request, so a small sample tells you nothing. Send 200 requests:

```sh
for i in $(seq 1 200); do
  kubectl -n starfleet exec deploy/shuttle -- curl -s http://scout:9080/reviews/0 | grep -o 'scout-v[0-9]'
done | sort | uniq -c
```

```text
 124 scout-v1
  49 scout-v2
  27 scout-v3
```

The shares are 124, 49 and 27 out of 200. They are close to 60%, 30% and 10%, and each count is inside the range that the task accepts. Your numbers will differ a little on each run.

---

## Item 5: There Is Exactly One `VirtualService` For `scout`

> **Task item 5:** There is exactly one `VirtualService` for `scout`.

```sh
kubectl get virtualservice -A | grep -c scout
kubectl -n starfleet get virtualservice -o custom-columns=NAME:.metadata.name,HOSTS:.spec.hosts
```

```text
1
NAME    HOSTS
scout   [scout]
```

One `VirtualService` exists for `scout`, in all namespaces. Two objects for one host have no fixed order, so never add a second one. Change the existing one.

---

## Item 6: The `DestinationRule` Is Unchanged

> **Task item 6:** The `DestinationRule` named `scout` is **left unchanged**.

Run the two `DestinationRule` commands from the Start section again:

```sh
kubectl -n starfleet get destinationrule scout -o jsonpath='generation={.metadata.generation} uid={.metadata.uid}{"\n"}'
kubectl -n starfleet get destinationrule scout -o jsonpath='{range .spec.subsets[*]}{.name}={.labels.version}{"\n"}{end}'
```

```text
generation=1 uid=558fb5c2-d35d-4141-8f76-ad745d3762ab
v1=v1
v2=v2
v3=v3
```

The `generation` is still `1`, so nobody edited the object. The subsets are the same.

---

## Item 7: The Workloads Are Unchanged

> **Task item 7:** Leave the Deployments, their replica counts, their pod labels and the Services unchanged. Do not add or remove workloads.

Run the Deployment and Service commands from the Start section again:

```sh
kubectl -n starfleet get deploy -o custom-columns=NAME:.metadata.name,REPLICAS:.spec.replicas,UID:.metadata.uid
kubectl -n starfleet get svc -o custom-columns=NAME:.metadata.name,PORT:.spec.ports[0].port,SELECTOR:.spec.selector
```

```text
NAME        REPLICAS   UID
bridge-v1   1          d7709143-621c-4407-9644-ecdac2d0c469
cargo-v1    1          f6140560-ae4d-4b3f-a8ca-3fe4a2e2d29e
navcom-v1   1          a1d3d77c-9836-4834-b209-2497bfb248b3
scout-v1    1          b008278d-5994-4f76-9cab-81ee6aef0bf8
scout-v2    1          3a323752-3cd9-4b82-b3bf-ce40f0aee927
scout-v3    1          9b12e9a5-fa1b-4fa3-bccd-89f43e300f6d
shuttle     1          cf0f18a9-6da6-467b-9036-54c84f5cdbbd
NAME     PORT   SELECTOR
bridge   9080   map[app:bridge]
cargo    9080   map[app:cargo]
navcom   9080   map[app:navcom]
scout    9080   map[app:scout]
```

The output is the same as before. The same seven Deployments exist with one replica each, and the Services are the same. The share comes from the weights, not from the pod count.

---

## Submit

Send the lab for grading:

```sh
astrona submit -c sections/section-020/module-01/labs/lab-02
```

The grader sends live requests from the `shuttle` pod and reads the configuration of its proxy.

---

## Mistakes That Fail The Grader

- **Leaving a destination without a weight (item 2).** On the starting state the grader reports `v1=no weight`. Every destination in a split needs its own weight.
- **Nesting `weight` inside `destination` (item 2).** Kubernetes rejects the object, so nothing changes.
- **Weights that do not add up to 100, such as 60, 30 and 20 (item 2).** Istio accepts them as a ratio, but the grader expects exactly 60, 30 and 10.
- **Three separate `http` rules (item 1).** The first rule without `match` takes every request, so nothing is split. Put all three destinations in one route list.
- **A `match` on the rule (item 1).** The split must apply to every `scout` request.
- **Scaling the Deployments (item 7).** The share is set by weights, not by pod count, and the grader checks the replica counts.
- **A second `VirtualService` for `scout` (item 5).** Two objects for one host have no fixed order. Change the existing one.
