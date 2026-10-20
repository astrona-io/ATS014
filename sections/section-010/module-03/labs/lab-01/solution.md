# Solution Walkthrough

This task is a migration, so the order of the changes matters more than the YAML. The `patrol` pod sends a request every half second for the whole lab. One moment in which a route points at a missing subset is enough to fail the lab. The walkthrough therefore changes the `VirtualService` first (item 1), checks that the proxies have it, and only then removes `v1` from the `DestinationRule` (item 2). Items 3 to 6 prove that the result is correct and safe.

---

## Start: Read The Starting State

The task says that a `VirtualService` sends every request to `v1`, and that a `DestinationRule` defines `v1`, `v2` and `v3`. Look at both objects, and at where requests go now:

```sh
kubectl -n starfleet get virtualservice scout -o jsonpath='{.spec.http}{"\n"}'
kubectl -n starfleet get destinationrule scout -o jsonpath='{.spec.subsets[*].name}{"\n"}'
for i in $(seq 1 10); do
  kubectl -n starfleet exec deploy/shuttle -- curl -s http://scout:9080/reviews/0 | grep -o 'scout-v[0-9]'
done | sort | uniq -c
```

```text
[{"route":[{"destination":{"host":"scout","subset":"v1"}}]}]
v1 v2 v3
  10 scout-v1
```

Every request goes to `v1`, and all three subsets exist. A subset is a named group of pods, picked by labels. Two objects must change, and the order is the question.

The `VirtualService` points at the subsets of the `DestinationRule`. That gives two rules for the order:

- To add a route, the subset that it uses must already exist.
- To remove a subset, first stop every route from using it, and only then remove it.

`v2` and `v3` already exist. So the `VirtualService` can change first, and the `DestinationRule` changes last.

Save the identity of the workloads and Services. Item 6 compares against it:

```sh
kubectl -n starfleet get deploy -o custom-columns=NAME:.metadata.name,UID:.metadata.uid
kubectl -n starfleet get svc -o custom-columns=NAME:.metadata.name,PORT:.spec.ports[0].port
```

```text
NAME        UID
bridge-v1   361056c9-7a42-4e58-9b4d-62204a0db693
cargo-v1    406881b4-d55b-4100-97db-a71a64900901
navcom-v1   4f51c1bd-696f-43cf-8227-6882dfa82f47
patrol      eb5eab54-fccc-4cf9-adbb-30c9a62d6b12
scout-v1    1b2ef2b1-c9b6-494a-ab7e-8f6b4e08988f
scout-v2    23683350-d677-4e76-bedc-12de3cfae2be
scout-v3    b6715c59-6b6b-4d36-932d-80dbd02fa669
shuttle     c1c505d6-dd4b-4646-ab16-396638c45ac3
NAME     PORT
bridge   9080
cargo    9080
navcom   9080
scout    9080
```

---

## Item 1: Change The `VirtualService` First

> **Task item 1:** The `VirtualService` named `scout` in `starfleet` has **exactly two rules**, in this order: requests with the header `end-user: jason` go to the subset **`v3`**, and every other request goes to the subset **`v2`**. Each rule has one destination.

A `VirtualService` holds the routing rules for a host. The proxy reads the rules from top to bottom and uses the first one that matches. So the `jason` rule must come first, and the rule without `match` must come last. Save this as `virtualservice-scout.yaml`:

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
  - match:
    - headers:
        end-user:
          exact: jason
    route:
    - destination:
        host: scout
        subset: v3
  - route:
    - destination:
        host: scout
        subset: v2
```

Apply it:

```sh
kubectl apply -f virtualservice-scout.yaml
```

```text
virtualservice.networking.istio.io/scout configured
```

Do not remove `v1` yet. First check that the new routes reached the proxy of `patrol`. The proxy is the Envoy container that Istio adds to each pod, and the grader judges the requests of `patrol`. Its route table for port `9080` must no longer mention `v1`:

```sh
istioctl proxy-config routes deploy/patrol -n starfleet --name 9080 -o json | grep '"cluster".*scout'
```

```text
                            "cluster": "outbound|9080|v3|scout.starfleet.svc.cluster.local",
                            "cluster": "outbound|9080|v2|scout.starfleet.svc.cluster.local",
```

Only `v3` and `v2` are left. If you still see `v1`, `istiod`, the Istio control plane, has not sent the new routes yet. Wait a few seconds and run the command again. Confirm the routing with requests from `shuttle`:

```sh
for i in $(seq 1 10); do
  kubectl -n starfleet exec deploy/shuttle -- curl -s -H "end-user: jason" http://scout:9080/reviews/0 | grep -o 'scout-v[0-9]'
done | sort | uniq -c
for i in $(seq 1 10); do
  kubectl -n starfleet exec deploy/shuttle -- curl -s http://scout:9080/reviews/0 | grep -o 'scout-v[0-9]'
done | sort | uniq -c
```

```text
  10 scout-v3
  10 scout-v2
```

No route uses `v1` any more. Now it is safe to remove the subset.

---

## Item 2: Remove `v1` From The `DestinationRule`

> **Task item 2:** The `DestinationRule` named `scout` defines **exactly two subsets**: `v2` and `v3`, each selecting `version` equal to its own name.

A `DestinationRule` holds the policies for traffic to one host, and it defines the subsets. Save this as `destinationrule-scout.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: scout
  namespace: starfleet
spec:
  host: scout
  subsets:
  - name: v2
    labels:
      version: v2
  - name: v3
    labels:
      version: v3
```

Apply it:

```sh
kubectl apply -f destinationrule-scout.yaml
```

```text
destinationrule.networking.istio.io/scout configured
```

Apply the changed object. Do not delete the `DestinationRule` and create a new one, because for a moment no subset would exist.

Check item 1 and item 2 together. Print the rules in order, and print the subsets with their label values:

```sh
kubectl -n starfleet get virtualservice scout \
  -o jsonpath='{range .spec.http[*]}{.match}{" -> "}{.route[*].destination.subset}{"\n"}{end}'
kubectl -n starfleet get destinationrule scout \
  -o jsonpath='{range .spec.subsets[*]}{.name}={.labels.version}{"\n"}{end}'
```

```text
[{"headers":{"end-user":{"exact":"jason"}}}] -> v3
 -> v2
v2=v2
v3=v3
```

The `VirtualService` has exactly two rules, with one destination each, and the `jason` rule is first. The `DestinationRule` has exactly the subsets `v2` and `v3`.

---

## Item 3: No Route Points At A Missing Subset

> **Task item 3:** No route points at a subset or host that does not exist (`istioctl analyze -n starfleet` reports no `IST0101`).

Run the analyzer, and list the clusters that the `patrol` proxy holds for `scout`. A cluster is a named destination in Envoy:

```sh
istioctl analyze -n starfleet
istioctl proxy-config clusters deploy/patrol -n starfleet | grep -E "SERVICE|scout"
```

```text

✔ No validation issues found when analyzing namespace: starfleet.
SERVICE FQDN                               PORT      SUBSET     DIRECTION     TYPE             DESTINATION RULE
scout.starfleet.svc.cluster.local          9080      -          outbound      EDS              scout.starfleet
scout.starfleet.svc.cluster.local          9080      v2         outbound      EDS              scout.starfleet
scout.starfleet.svc.cluster.local          9080      v3         outbound      EDS              scout.starfleet
```

The analyzer finds no problem. The `v1` cluster is gone from the proxy, and the `v2` and `v3` clusters remain.

---

## Item 4: The Requests Reach The Right Versions

> **Task item 4:** All 10 out of 10 requests sent with the header `end-user: jason` are answered by `scout-v3`, and all 10 out of 10 requests without it by `scout-v2`.

Send the two loops again, now that both objects are final:

```sh
for i in $(seq 1 10); do
  kubectl -n starfleet exec deploy/shuttle -- curl -s -H "end-user: jason" http://scout:9080/reviews/0 | grep -o 'scout-v[0-9]'
done | sort | uniq -c
for i in $(seq 1 10); do
  kubectl -n starfleet exec deploy/shuttle -- curl -s http://scout:9080/reviews/0 | grep -o 'scout-v[0-9]'
done | sort | uniq -c
```

```text
  10 scout-v3
  10 scout-v2
```

All requests with the header reached `scout-v3`, and all others reached `scout-v2`.

---

## Item 5: `patrol` Never Saw A Failed Request

> **Task item 5:** **The `patrol` pod never sees a failed request.** Its proxy's access log must not contain a single `5xx` response for `/reviews/0`, and it must hold at least 20 requests.

The access log of the `patrol` proxy has one line per request. The grader needs at least 20 requests in it, so wait about 30 seconds after your last change. Then count all lines for `/reviews/0`, and count the lines with a `5xx` status:

```sh
sleep 40
kubectl -n starfleet logs deploy/patrol -c istio-proxy | grep -c '/reviews/0'
kubectl -n starfleet logs deploy/patrol -c istio-proxy | grep '/reviews/0' | grep -cE '" 5[0-9][0-9] '
kubectl -n starfleet logs deploy/patrol -c istio-proxy --tail=1
```

```text
94
0
[2026-10-20T20:25:05.287Z] "GET /reviews/0 HTTP/1.1" 200 - via_upstream - "-" 0 440 30 30 "-" "curl/8.11.1" "43dcc425-6033-4d09-900a-6da371df7e85" "scout:9080" "10.244.0.9:9080" outbound|9080|v2|scout.starfleet.svc.cluster.local 10.244.0.13:58360 10.96.101.210:9080 10.244.0.13:38102 - -
```

The log holds 94 requests and none of them has a `5xx` status. The last line shows a `200` response from the `v2` cluster. If you tried a wrong order earlier, the log holds failures. Restart `patrol` with `kubectl -n starfleet rollout restart deploy/patrol`, and wait 30 seconds, so the log starts clean.

---

## Item 6: Nothing Else Changed

> **Task item 6:** Keep exactly one `VirtualService` for `scout`. Leave the Deployments, their pod labels and the Services unchanged, and do not stop or remove `patrol`.

```sh
kubectl -n starfleet get virtualservice
kubectl -n starfleet get deploy -o custom-columns=NAME:.metadata.name,UID:.metadata.uid
kubectl -n starfleet get svc -o custom-columns=NAME:.metadata.name,PORT:.spec.ports[0].port
kubectl -n starfleet get pods -L version | grep -E "NAME|patrol|scout"
```

```text
NAME    GATEWAYS   HOSTS       AGE
scout              ["scout"]   79s
NAME        UID
bridge-v1   361056c9-7a42-4e58-9b4d-62204a0db693
cargo-v1    406881b4-d55b-4100-97db-a71a64900901
navcom-v1   4f51c1bd-696f-43cf-8227-6882dfa82f47
patrol      eb5eab54-fccc-4cf9-adbb-30c9a62d6b12
scout-v1    1b2ef2b1-c9b6-494a-ab7e-8f6b4e08988f
scout-v2    23683350-d677-4e76-bedc-12de3cfae2be
scout-v3    b6715c59-6b6b-4d36-932d-80dbd02fa669
shuttle     c1c505d6-dd4b-4646-ab16-396638c45ac3
NAME     PORT
bridge   9080
cargo    9080
navcom   9080
scout    9080
NAME                         READY   STATUS    RESTARTS   AGE     VERSION
patrol-5f754d7d8-bpf25       2/2     Running   0          68s     
scout-v1-85bf65868-pxx4n     2/2     Running   0          2m14s   v1
scout-v2-866c98b568-znv8r    2/2     Running   0          2m14s   v2
scout-v3-668c6dfc68-xp87t    2/2     Running   0          2m14s   v3
```

There is one `VirtualService`. The Deployments have the same `UID` values, and `patrol` still runs. The `scout-v1` Deployment still exists: the task retires the subset `v1`, and it does not delete the workload.

---

## Submit

Send the lab for grading:

```sh
astrona submit -c sections/section-010/module-03/labs/lab-01
```

The grader sends live requests from the `shuttle` pod, runs `istioctl analyze`, and reads the access log of the `patrol` proxy.

---

## Mistakes That Fail The Grader

- **Removing `v1` from the `DestinationRule` first (items 1 and 2, and so item 5).** The `VirtualService` still sends every request to `v1`. The proxies answer `503` with the response flag `NC` ("no cluster") until the new routes arrive, and the `patrol` proxy logs every one of those requests.
- **Applying both files at once (items 1 and 2).** `kubectl apply -f` on both files gives the proxies no time between the two changes. Change the `VirtualService`, check that it arrived, then remove the subset.
- **Putting the rule without `match` first (item 1).** A rule without `match` matches every request, so requests from `jason` would never reach `v3`.
- **Deleting the `DestinationRule` and creating a new one (item 2).** For a moment there are no subsets, and every route fails. Apply the changed object instead.
- **Stopping or deleting `patrol` (items 5 and 6).** The grader needs its access log. If the log holds earlier mistakes, restart `patrol`, wait at least 30 seconds, and submit again.
