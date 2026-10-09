# Solution Walkthrough

A `DestinationRule` defines **subsets**, named groups of a Service's pods selected by a label. A `VirtualService` tells the sidecar proxies where to send requests for a host. The `DestinationRule` is already correct, so this lab is only about the `VirtualService`: one route, three destinations, and three weights that add up to 100.

---

## Step 1: Read the starting state

Look at the `VirtualService` you were given:

```sh
kubectl get virtualservice scout -n starfleet -o yaml
```

You should see this (shortened to `spec`):

```text
spec:
  hosts:
  - scout
  http:
  - route:
    - destination:
        host: scout
        subset: v1
```

It has one destination and no weight. Count where the requests go today:

```sh
for i in $(seq 1 20); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s http://scout:9080/reviews/0 | grep -o 'scout-v[0-9]'
done | sort | uniq -c
```

You should see:

```text
  20 scout-v1
```

Every request goes to v1. The v2 and v3 pods are running, but no route sends them a request.

---

## Step 2: Write the three-way split

Put all three destinations in the **same** route list, and give each one a `weight` next to its `destination` (not inside it). The weight is the destination's share of the requests. Save this as `virtualservice-scout.yaml`:

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

---

## Step 3: Check the weights reached the proxy

`istiod`, Istio's control plane, sends the new route to every sidecar proxy. Ask the `shuttle` proxy for the weights it holds:

```sh
istioctl proxy-config routes deploy/shuttle -n starfleet --name 9080 -o json \
  | grep -A16 weightedClusters | grep -E '"name"|"weight"'
```

You should see:

```text
                                        "name": "outbound|9080|v1|scout.starfleet.svc.cluster.local",
                                        "weight": 60
                                        "name": "outbound|9080|v2|scout.starfleet.svc.cluster.local",
                                        "weight": 30
                                        "name": "outbound|9080|v3|scout.starfleet.svc.cluster.local",
                                        "weight": 10
```

There is one Envoy **cluster** (a named destination) per subset, each with the weight you wrote. The new route has reached the proxy.

---

## Step 4: Measure the split

Count 100 requests:

```sh
for i in $(seq 1 100); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s http://scout:9080/reviews/0 | grep -o 'scout-v[0-9]'
done | sort | uniq -c
```

You should see something like:

```text
  58 scout-v1
  34 scout-v2
   8 scout-v3
```

The split is close to 60/30/10, but not exact: the proxy makes a separate random pick for each request. Your numbers will be a little different.

---

## Step 5: Submit

```sh
astrona submit -c sections/section-020/module-01/labs/lab-02
```

You should see this (shortened):

```text
PASS: one VirtualService sends the scout v1 60, v2 30 and v3 10, the shuttle's proxy holds those weights, the DestinationRule and deployments are unchanged, and 200 live requests split v1=129 v2=54 v3=17 of 200
PROCTOR: PASS
```

---

## Mistakes that fail the grader

- **Leaving a destination without a weight.** On the starting state the grader reports `the route sends [v1=no weight]`. Every destination in a split needs its own weight.
- **Nesting `weight` inside `destination`.** Kubernetes rejects the object, so nothing changes.
- **Weights that do not add up to 100**, such as 60, 30 and 20. Istio accepts them as a ratio, but the grader expects exactly 60, 30 and 10.
- **Three separate `http` rules.** The first rule with no `match` takes every request, so nothing is split. Put all three destinations in one route list.
- **A `match` on the rule.** The split must apply to every `scout` request.
- **Scaling the Deployments.** The grader checks that every `scout` version still runs 1 replica. The share is set by weights, not by pod count.
- **A second `VirtualService` for `scout`.** Two `VirtualService` objects for one host have no set order. Change the existing one.
