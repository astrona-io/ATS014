# Solution Walkthrough

Mission debrief, astronaut. The docking instructions are already correct, so this mission is only about the flight plan: one route, three destinations, three weights that add up to 100.

---

## Step 1: Read the starting state

Look at the flight plan you were given:

```sh
kubectl get virtualservice scout -n starfleet -o yaml
```

You should see (trimmed to `spec`):

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

One destination, no weight. Count where the signals go today:

```sh
for i in $(seq 1 20); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s http://scout:9080/reviews/0 | grep -o 'scout-v[0-9]'
done | sort | uniq -c
```

You should see:

```text
  20 scout-v1
```

Every signal flies to v1. v2 and v3 are running, but nothing sends them a signal.

---

## Step 2: Write the three-way split

Put all three destinations in the **same** route list, and give each one a `weight` next to its `destination` (not inside it). Save this as `virtualservice-scout.yaml`:

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

The object keeps its name, so `kubectl apply` replaces the old flight plan. You do not delete anything first.

---

## Step 3: Check the weights reached the proxy

Ask the shuttle's proxy for the weights it holds:

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

One cluster per subset, each with the weight you wrote. The flight plan has arrived.

---

## Step 4: Measure the split

Count 100 signals:

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

Close to 60/30/10, but not exact: each signal is a separate random roll. Your numbers will be a little different.

---

## Step 5: Submit

```sh
astrona submit -c sections/section-020/module-01/labs/lab-02
```

You should see (trimmed):

```text
PASS: one flight plan sends the scout v1 60, v2 30 and v3 10, the shuttle's proxy holds those weights, the docking instructions and ships are unchanged, and 200 live signals split v1=129 v2=54 v3=17 of 200
PROCTOR: PASS
```

---

## Mistakes that fail the grader

- **Leaving a destination without a weight.** On the starting state the grader reports `the route sends [v1=no weight]`. Every destination in a split needs its own weight.
- **Nesting `weight` inside `destination`.** Kubernetes rejects the object, so nothing changes.
- **Weights that do not add up to 100**, such as 60, 30 and 20. Istio accepts them as a ratio, but the grader expects exactly 60, 30 and 10.
- **Three separate `http` rules.** The first rule with no `match` takes every signal, so nothing is split. Put all three destinations in one route list.
- **A `match` on the rule.** The split must apply to every scout signal.
- **Scaling the ships.** The grader checks that every scout version still runs 1 replica. The share is set by weights, not by pod count.
- **A second `VirtualService` for the scout.** Two flight plans for one beacon have no set order. Change the existing one.
