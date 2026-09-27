# Solution Walkthrough

Two objects, and the trick is that the thing you are building is invisible from where you normally look. The caller's output is identical whether the mirror works or not, so the verification is the interesting half.

---

## Step 1: Read the Starting State

```sh
kubectl -n mirror-demo get pods --show-labels
kubectl -n mirror-demo get destinationrule,virtualservice
kubectl -n mirror-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 20); do curl -s -X POST http://notification-service/notify; echo; done' | sort | uniq -c
```

```text
notification-service-v1-5b9c7d8f4-2ktzn   2/2   Running   app=notification-service,version=v1,...
notification-service-v2-7f8d6c5b9-lq4wm   2/2   Running   app=notification-service,version=v2,...
tester-6d4f8b7c5-9xnpk                    2/2   Running   app=tester,...
No resources found in mirror-demo namespace.
  12 ["EMAIL"]
   8 ["EMAIL","SMS"]
```

Both versions currently answer callers. The finished state must show only `["EMAIL"]` — while `v2` is busier than it is now.

---

## Step 2: Define the Subsets

```sh
kubectl apply -f - <<'EOF'
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: notification-service
  namespace: mirror-demo
spec:
  host: notification-service
  subsets:
    - name: v1
      labels:
        version: v1
    - name: v2
      labels:
        version: v2
EOF
```

The `v2` subset matters more than usual here. A `mirror` pointing at a subset that does not exist, or at one whose labels select no pod, **silently does nothing** — and the caller cannot tell. Confirm it selects something:

```sh
istioctl proxy-config endpoints deploy/tester -n mirror-demo \
  --cluster "outbound|80|v2|notification-service.mirror-demo.svc.cluster.local"
```

```text
ENDPOINT            STATUS    OUTLIER CHECK   CLUSTER
10.244.0.15:8084    HEALTHY   OK              outbound|80|v2|notification-service...
```

---

## Step 3: Route To v1, Mirror To v2

```sh
kubectl apply -f - <<'EOF'
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: notification
  namespace: mirror-demo
spec:
  hosts:
    - notification-service
  http:
    - route:
        - destination:
            host: notification-service
            subset: v1
          weight: 100
      mirror:
        host: notification-service
        subset: v2
      mirrorPercentage:
        value: 100.0
EOF
istioctl analyze -n mirror-demo
```

```text
virtualservice.networking.istio.io/notification created
✔ No validation issues found when analyzing namespace: mirror-demo.
```

The indentation is the whole exercise. `mirror` and `mirrorPercentage` are **siblings of `route`** on the same `http` rule — not entries inside the route list. Writing `v2` as a second destination in `route` would make it a weighted split, callers would start seeing `["EMAIL","SMS"]`, and the grader rejects it.

Note also that `mirror` is a single destination with no `weight`. The copy is extra traffic on top of the route, not a share of it.

---

## Step 4: Confirm the Caller Sees Only v1

```sh
kubectl -n mirror-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 30); do curl -s -X POST http://notification-service/notify; echo; done' | sort | uniq -c
```

```text
  30 ["EMAIL"]
```

Thirty requests, one distinct answer. Any `["EMAIL","SMS"]` here means `v2` ended up in the route block rather than in the mirror.

This output is exactly what you would get with no mirror at all, which is why it proves only half the task.

---

## Step 5: Prove the Shadow Received the Copies

The evidence is on the **receiving** side, in the proxy access log, where Istio's rewritten authority is visible. Take a baseline first — the log may already hold copies from an earlier attempt:

```sh
BEFORE=$(kubectl -n mirror-demo logs -l version=v2 -c istio-proxy --tail=-1 | grep -c -- -shadow)
kubectl -n mirror-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 40); do curl -s -o /dev/null -X POST http://notification-service/notify; done'
sleep 3
AFTER=$(kubectl -n mirror-demo logs -l version=v2 -c istio-proxy --tail=-1 | grep -c -- -shadow)
echo "mirrored this run: $((AFTER - BEFORE)) of 40"
```

```text
mirrored this run: 40 of 40
```

Look at one of the lines to see why it counts as proof:

```sh
kubectl -n mirror-demo logs -l version=v2 -c istio-proxy --tail=3 | grep -i shadow
```

```text
[2026-09-27T10:14:02.771Z] "POST /notify HTTP/1.1" 200 - via_upstream - "-" 0 16 1 1 "-" "curl/8.5.0" "9b1a..." "notification-service-shadow" "10.244.0.15:8084" ...
```

`notification-service-shadow` is the authority Istio rewrote on the copy. The `200` next to it is the shadow's own response — which the caller never saw. If `v2` were returning 500s, this is where it would show, with the caller still perfectly happy.

---

## Step 6: Confirm the Policy Is in the Client Proxy

This is the check that separates "the mirror is misconfigured" from "the mirror target has no endpoints":

```sh
istioctl proxy-config routes deploy/tester -n mirror-demo -o json | grep -i -A6 requestMirrorPolicies
```

```text
"requestMirrorPolicies": [
  {
    "cluster": "outbound|80|v2|notification-service.mirror-demo.svc.cluster.local",
    "runtimeFraction": {
      "defaultValue": {
        "numerator": 100,
```

Note it is the **caller's** proxy that holds this — the caller is what dispatches the copy.

Three states worth remembering:

| `requestMirrorPolicies` | Shadow log | Means |
| --- | --- | --- |
| absent | empty | no `mirror` in the object, or it never reached the proxy |
| present | empty | the mirror cluster has no endpoints |
| present | `-shadow` lines | working |

---

## Common Mistakes

- **`mirror` indented as an entry of `route`.** It is a sibling of `route`, and a single destination rather than a list.
- **Putting `v2` in the route block as a weighted destination.** That is traffic shifting, and callers start seeing the candidate's output.
- **Mirroring to an undefined subset.** Silent — the caller is unaffected and the shadow is quiet. `istioctl analyze` names it.
- **Counting shadow log lines without a baseline.** The log holds copies from earlier runs; take a `BEFORE` count.
- **Reading application logs instead of the proxy log.** The `-shadow` authority is in the `istio-proxy` container's log.
- **Expecting the mirrored response to matter.** It is discarded, along with its latency. Mirroring cannot compare outputs.
- **Omitting `mirrorPercentage` and assuming nothing is mirrored.** The default is 100%; the task asks you to state it anyway.
