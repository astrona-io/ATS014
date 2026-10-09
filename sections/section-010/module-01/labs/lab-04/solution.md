# Solution Walkthrough

Mission debrief, astronaut. The flight plan had three faults stacked on top of each other: it sat on the wrong planet, its catch-all came first, and its jason rule asked for a ship class that does not exist. Each fault hid the next one, so you fix them one at a time and watch the symptom change.

---

## Step 1: See the symptom

Send 10 signals as jason, then 10 without a label, and count which scout ship answered:

```sh
for i in $(seq 1 10); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s -H "end-user: jason" http://scout:9080/reviews/0 | grep -o 'scout-v[0-9]'
done | sort | uniq -c
for i in $(seq 1 10); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s http://scout:9080/reviews/0 | grep -o 'scout-v[0-9]'
done | sort | uniq -c
```

```text
   1 scout-v1
   2 scout-v2
   7 scout-v3
   1 scout-v1
   9 scout-v3
```

A random mix for both. The flight plan is not steering anything. Read the last line of the shuttle's flight log:

```sh
kubectl logs -n starfleet deploy/shuttle -c istio-proxy --tail=1
```

```text
[2026-10-08T19:42:51.672Z] "GET /reviews/0 HTTP/1.1" 200 - via_upstream - "-" 0 436 7 7 "-" "curl/8.11.1" "d71701cd-ba45-4e8b-bfcf-15a38de51226" "scout:9080" "10.244.0.10:9080" outbound|9080||scout.starfleet.svc.cluster.local 10.244.0.12:39494 10.96.51.189:9080 10.244.0.12:44222 - default
```

Status `200`, flag `-`, and the cluster `outbound|9080||scout...` with an empty subset field. Nothing failed: the signal simply used the plain scout cluster, as if no flight plan existed at all.

## Step 2: Find where the flight plan lives

`istioctl analyze -n starfleet` is clean:

```sh
istioctl analyze -n starfleet
```

```text
✔ No validation issues found when analyzing namespace: starfleet.
```

So look on every planet:

```sh
kubectl get virtualservice,destinationrule -A
```

```text
NAMESPACE   NAME                                       GATEWAYS   HOSTS       AGE
default     virtualservice.networking.istio.io/scout              ["scout"]   9s

NAMESPACE   NAME                                        HOST    AGE
starfleet   destinationrule.networking.istio.io/scout   scout   9s
```

The flight plan lives in `default`, with the short host `scout`. On that planet the short name means `scout.default.svc.cluster.local`, a beacon that does not exist. That is fault 1. Now check every planet with `istioctl analyze`:

```sh
istioctl analyze -A
```

```text
Error [IST0101] (VirtualService default/scout) Referenced host not found: "scout"
Error [IST0101] (VirtualService default/scout) Referenced host+subset in destinationrule not found: "scout+v1"
Error [IST0101] (VirtualService default/scout) Referenced host+subset in destinationrule not found: "scout+v4"
Warning [IST0130] (VirtualService default/scout) VirtualService rule #1 not used (route without matches defined before).
Info [IST0102] (Namespace default) The namespace is not enabled for Istio injection. Run 'kubectl label namespace default istio-injection=enabled' to enable it, or 'kubectl label namespace default istio-injection=disabled' to explicitly mark it as not needing injection.
```

`analyze -A` names all three faults:

- `Referenced host not found: "scout"` is the wrong planet.
- `IST0130 ... rule #1 not used` is the catch-all placed first.
- `scout+v4` is a subset the `DestinationRule` never defines.

The `IST0102` line only says that `default` has no sidecar injection. It does not matter for this mission.

## Step 3: Move the flight plan to the right planet

Fix one fault at a time, so you can see each symptom change. Remove the flight plan from `default`:

```sh
kubectl delete virtualservice scout -n default
```

```text
virtualservice.networking.istio.io "scout" deleted from default namespace
```

Save the same flight plan, still with its other two faults, for `starfleet`. Save this as `virtualservice-scout.yaml`:

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
  - match:
    - headers:
        end-user:
          exact: jason
    route:
    - destination:
        host: scout
        subset: v4
```

Apply it:

```sh
kubectl apply -f virtualservice-scout.yaml
```

```text
Warning: virtualService rule #1 not used (route without matches defined before)
virtualservice.networking.istio.io/scout created
```

Then send 10 signals as jason again, and 10 without a label:

```sh
for i in $(seq 1 10); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s -H "end-user: jason" http://scout:9080/reviews/0 | grep -o 'scout-v[0-9]'
done | sort | uniq -c
for i in $(seq 1 10); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s http://scout:9080/reviews/0 | grep -o 'scout-v[0-9]'
done | sort | uniq -c
```

```text
  10 scout-v1
  10 scout-v1
```

The flight plan now steers signals: everything flies to v1. But jason flies to v1 too. `kubectl apply` already warned why: the catch-all comes first, so the proxy stops there and never reaches jason's rule. That is fault 2.

## Step 4: Put the catch-all last

Swap the two rules in `virtualservice-scout.yaml`, so the jason rule comes first. Save this as `virtualservice-scout.yaml`:

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
        subset: v4
  - route:
    - destination:
        host: scout
        subset: v1
```

Apply it:

```sh
kubectl apply -f virtualservice-scout.yaml
```

Then send one signal as jason and read the flight log:

```sh
kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" -H "end-user: jason" http://scout:9080/reviews/0
kubectl logs -n starfleet deploy/shuttle -c istio-proxy --tail=1
```

```text
503
[2026-10-08T19:43:35.381Z] "GET /reviews/0 HTTP/1.1" 503 NC cluster_not_found - "-" 0 0 0 - "-" "curl/8.11.1" "21c2f382-8f3a-4b1b-972b-19de034bc42d" "scout:9080" "-" - - 10.96.51.189:9080 10.244.0.12:54662 - -
```

Now jason's rule fires, and it fails with `503` and the flag **`NC`**, "no cluster". The rule asks for subset `v4`, and the `DestinationRule` only defines `v1`, `v2` and `v3`. That is fault 3.

## Step 5: Fix the subset name

Change `subset: v4` to `subset: v2`. Save this as `virtualservice-scout.yaml`:

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
        subset: v2
  - route:
    - destination:
        host: scout
        subset: v1
```

Apply it:

```sh
kubectl apply -f virtualservice-scout.yaml
```

Then send 10 signals as jason, and 10 without a label:

```sh
for i in $(seq 1 10); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s -H "end-user: jason" http://scout:9080/reviews/0 | grep -o 'scout-v[0-9]'
done | sort | uniq -c
for i in $(seq 1 10); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s http://scout:9080/reviews/0 | grep -o 'scout-v[0-9]'
done | sort | uniq -c
```

```text
  10 scout-v2
  10 scout-v1
```

And check every planet once more:

```sh
istioctl analyze -A
```

```text
Info [IST0102] (Namespace default) The namespace is not enabled for Istio injection. Run 'kubectl label namespace default istio-injection=enabled' to enable it, or 'kubectl label namespace default istio-injection=disabled' to explicitly mark it as not needing injection.
```

No `IST0101` and no `IST0130` left: only the note about `default`, which has nothing to do with the flight plan.

## Step 6: Submit

```sh
astrona submit -c sections/section-010/module-01/labs/lab-04
```

```text
PASS: one flight plan (starfleet/scout) describes scout.starfleet.svc.cluster.local, jason's rule comes first with subset v2, the catch-all sends to v1, istioctl analyze is clean for it, jason reaches scout-v2 and everyone else scout-v1
```

## The other way to fix the planet

Instead of moving the flight plan, you can leave it in `default` and write the full name `scout.starfleet.svc.cluster.local` in `hosts` and in every `destination.host`. A full name means the same beacon on every planet, so that passes too. Do not do both: two flight plans for the same beacon fail the grader.

## Mistakes that fail the grader

- **Fixing only what you can see.** Each fault hides the next one. Moving the flight plan alone leaves jason on v1. Reordering alone leaves him on `503 NC`.
- **Leaving the short host `scout` in `default`.** It describes `scout.default.svc.cluster.local`, so no rule ever fires.
- **Keeping the old flight plan as well as the new one.** Two `VirtualService` objects for the same beacon have no set order between them. The grader wants exactly one.
- **Fixing the subset by changing the `DestinationRule`.** The docking instructions were correct. The typo is in the flight plan.
- **Trusting `istioctl analyze -n starfleet`.** It only checks `starfleet`. Use `-A` when you do not know where an object lives.
