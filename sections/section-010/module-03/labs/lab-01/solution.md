# Solution Walkthrough

Mission debrief, astronaut. The end state is two small objects. The real task was the order: the patrol was watching the whole time, and one moment where a route pointed at a missing subset was enough to fail.

---

## Step 1: Read the starting state

Look at the flight plan, the subsets, and where the signals go now:

```sh
kubectl get virtualservice scout -n starfleet -o jsonpath='{.spec.http}'; echo
kubectl get destinationrule scout -n starfleet -o jsonpath='{.spec.subsets[*].name}'; echo
for i in $(seq 1 10); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s http://scout:9080/reviews/0 | grep -o 'scout-v[0-9]'
done | sort | uniq -c
```

```text
[{"route":[{"destination":{"host":"scout","subset":"v1"}}]}]
v1 v2 v3
  10 scout-v1
```

Every signal flies to `v1`, and all three subsets exist. Two objects must change. The question is which one first.

## Step 2: Pick the order

The flight plan points at the subsets. So:

- **Removing** a subset: first stop every route from using it, then remove it.
- **Adding** a route: the subsets it uses must already exist.

Here `v2` and `v3` already exist, so the flight plan can change first, safely. Only after every proxy has the new flight plan may `v1` disappear from the docking instructions.

## Step 3: Change the flight plan first

Save this as `virtualservice-scout.yaml`:

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

## Step 4: Check that the new flight plan arrived

The patrol is the ship whose signals are judged, so check its proxy. Its route table must no longer mention `v1`:

```sh
istioctl proxy-config routes deploy/patrol -n starfleet --name 9080 -o json | grep '"cluster".*scout'
```

```text
                            "cluster": "outbound|9080|v3|scout.starfleet.svc.cluster.local",
                            "cluster": "outbound|9080|v2|scout.starfleet.svc.cluster.local",
```

Only `v3` and `v2` are left. Confirm the signals from the shuttle too:

```sh
for i in $(seq 1 10); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s -H "end-user: jason" http://scout:9080/reviews/0 | grep -o 'scout-v[0-9]'
done | sort | uniq -c
for i in $(seq 1 10); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s http://scout:9080/reviews/0 | grep -o 'scout-v[0-9]'
done | sort | uniq -c
```

```text
  10 scout-v3
  10 scout-v2
```

No route uses `v1` any more. Now it is safe to remove it.

## Step 5: Remove the old subset

Save this as `destinationrule-scout.yaml`:

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

## Step 6: Prove nothing broke

Check the patrol's clusters, run `istioctl analyze`, and read the patrol's last flight log line:

```sh
istioctl proxy-config clusters deploy/patrol -n starfleet | grep scout
istioctl analyze -n starfleet
kubectl logs -n starfleet deploy/patrol -c istio-proxy --tail=1
```

```text
scout.starfleet.svc.cluster.local          9080      -          outbound      EDS              scout.starfleet
scout.starfleet.svc.cluster.local          9080      v2         outbound      EDS              scout.starfleet
scout.starfleet.svc.cluster.local          9080      v3         outbound      EDS              scout.starfleet
✔ No validation issues found when analyzing namespace: starfleet.
[2026-10-08T20:30:24.055Z] "GET /reviews/0 HTTP/1.1" 200 - via_upstream - "-" 0 440 8 7 "-" "curl/8.11.1" "4aaa55aa-741d-4612-bd58-3cbbdca991cd" "scout:9080" "10.244.0.8:9080" outbound|9080|v2|scout.starfleet.svc.cluster.local 10.244.0.14:46486 10.96.158.43:9080 10.244.0.14:51132 - -
```

The `v1` cluster is gone, the objects agree, and the patrol's signals land on `v2` with `200`. Submit:

```sh
astrona submit -c sections/section-010/module-03/labs/lab-01
```

```text
PASS: v1 is retired - jason flies to scout-v3, everyone else to scout-v2, the DestinationRule holds only v2 and v3, no route points at a missing subset, and the patrol logged 82 signals without a single failure
```

---

## Common Mistakes

- **Removing `v1` from the `DestinationRule` first.** The flight plan still sends every signal to `v1`, and the proxies answer `503 NC` until the new flight plan arrives. The patrol logs every one of them. On a test run, this order gave:

  ```text
  "GET /reviews/0 HTTP/1.1" 503 NC cluster_not_found ...
  ```

  and the grader answered: `the patrol logged 40 failed signals during your change (first one: 503 NC)`.
- **Applying both files at once.** `kubectl apply -f` on both files, or one file holding both objects, gives the proxies no time between the two changes. Change the flight plan, check that it arrived, then remove the subset.
- **Putting the catch-all first.** The jason rule must come first. A rule without `match` fits every signal, so jason would never reach `v3`.
- **Deleting the `DestinationRule` and creating a new one.** For a moment there are no subsets at all, and every route fails with `503 NC`. Apply the changed object instead: `kubectl apply` replaces it in one step.
- **Stopping or deleting the patrol.** It is part of the mission. If its log is full of earlier mistakes, restart it, wait at least 30 seconds, and submit again.
