# Solution Walkthrough

One object, two rules. The scoping is not decoration — the grader sends unmarked traffic and fails you if it is affected.

---

## Step 1: Establish the Baseline

```sh
kubectl -n fault-demo get virtualservice
kubectl -n fault-demo run t0 --rm -i --restart=Never --image=curlimages/curl -- \
  curl -s -o /dev/null -w '%{http_code} %{time_total}s\n' -X POST http://booking-service/book
```

```text
No resources found in fault-demo namespace.
200 0.043s
```

Forty milliseconds across two hops. Both numbers matter: the status is what the abort would change, the latency is what the delay changes.

---

## Step 2: Work Out Where the Timeout Has to Live

The task asks for a 7-second delay **and** a 500 abort on one rule, and a
3-second timeout on a **different object**. That split is the whole exercise, so
work out why before applying anything.

An injected delay is produced by the **fault filter**, which runs before the
router in the same proxy. A `timeout` on that same rule is a *route* timeout: it
measures the upstream request, which has not started yet while the fault filter
is holding the request. Put both on one rule and the timeout never sees the
delay — the request waits the full seven seconds and then gets the abort's 500.

```text
  client ──────────────► booking-service ──────────────► notification-service
         │                               │
         │ timeout: 3s                   │ fault: delay 7s + abort 500
         │ (enforced in the CLIENT's     │ (enforced in BOOKING-SERVICE's
         │  proxy, on the outer call)    │  proxy, on the inner call)
         │                               │
         ▼                               ▼
   at t=3s: 504 UT              still holding, never reached
```

The delay runs on the inner hop. The timeout on the **outer** hop cuts the whole
exchange off at three seconds, which is before the seven-second hold completes —
so the abort never gets its turn. The observable result is a **504 at about
3 seconds**, not a 500 at 7.

That is the point of the exercise: a fabricated delay is how you make a timeout
fire on demand, reproducibly, without waiting for a real slow dependency — and a
timeout only fires against a delay that some *other* proxy is producing.

---

## Step 3: Write Both Rules

Write the manifest to a file and apply the file. It is the habit the exam rewards — you get something you can re-read, edit and re-apply, instead of a heredoc that is gone the moment it runs.

```sh
cat > virtualservice-notification.yaml <<'EOF'
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: notification
  namespace: fault-demo
spec:
  hosts:
    - notification-service
  http:
    - match:
        - headers:
            end-user:
              exact: tester
      fault:
        delay:
          fixedDelay: 7s
          percentage:
            value: 100
        abort:
          httpStatus: 500
          percentage:
            value: 100
      route:
        - destination:
            host: notification-service
    - route:
        - destination:
            host: notification-service
EOF
kubectl apply -f virtualservice-notification.yaml
cat > virtualservice-booking.yaml <<'EOF'
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: booking
  namespace: fault-demo
spec:
  hosts:
    - booking-service
  http:
    - timeout: 3s
      route:
        - destination:
            host: booking-service
EOF
kubectl apply -f virtualservice-booking.yaml
istioctl analyze -n fault-demo
```

```text
virtualservice.networking.istio.io/notification created
virtualservice.networking.istio.io/booking created
✔ No validation issues found when analyzing namespace: fault-demo.
```

Three things the grader checks specifically:

- **`hosts: [notification-service]`**, not `booking-service`. The fault belongs on the host you are pretending is broken. Putting it on `booking-service` would delay the inbound request from curl — a different experiment entirely.
- **The scoped rule is first.** The catch-all has no `match`, so it matches everything; below it, the header rule would be dead.
- **The second rule is clean** — no fault, no timeout. That is what keeps everyone else's traffic working.
- **The timeout is on the `booking-service` object**, not beside the fault. Next to the delay it would be inert, as step 2 works through.

---

## Step 4: Confirm the Fault Is in the Caller's Proxy

```sh
istioctl proxy-config routes deploy/booking-service-v1 -n fault-demo -o json | grep -i -A8 '"fault"'
```

```text
"fault": {
  "delay": {
    "fixedDelay": "7s",
    "percentage": {
      "numerator": 100,
      "denominator": "HUNDRED"
```

Note which proxy that is: **`booking-service`**, the caller. The [`VirtualService`](https://istio.io/latest/docs/reference/config/networking/virtual-service/) is keyed by the callee's hostname, but the filter runs in the calling workload's sidecar.

---

## Step 5: Verify Unmarked Traffic Is Untouched

Do this **before** testing your own request — it is the check that distinguishes a test from an outage:

```sh
for i in 1 2 3 4 5; do
  kubectl -n fault-demo run "u$i" --rm -i --restart=Never --image=curlimages/curl --quiet -- \
    curl -s -o /dev/null -w '%{http_code} %{time_total}s\n' -X POST http://booking-service/book
done
```

```text
200 0.041s
200 0.038s
200 0.044s
200 0.039s
200 0.042s
```

Five for five, fast. Everyone else's traffic is exactly as it was.

---

## Step 6: Verify the Marked Request

```sh
kubectl -n fault-demo run t1 --rm -i --restart=Never --image=curlimages/curl -- \
  curl -s -o /dev/null -w '%{http_code} %{time_total}s\n' -H "end-user: tester" -X POST http://booking-service/book
```

```text
504 3.052s
```

Three seconds, not seven, and a 504 rather than the 500 you configured — exactly as predicted in step 2.

If this returned `200`, the header did not reach the second hop. `booking-service` forwards request headers, which is what makes this work; a service that does not propagate headers cannot be tested this way, and that is a property of the application rather than of your configuration.

---

## Step 7: Prove the Timeout Fired

```sh
kubectl -n fault-demo logs deploy/tester -c istio-proxy --tail=-1 | grep ' 504 UT ' | tail -1
kubectl -n fault-demo logs -l app=booking-service -c istio-proxy --tail=10 | grep ' FI '
```

```text
[2026-09-28T19:03:07.140Z] "POST /book HTTP/1.1" 504 UT response_timeout - "-" 0 24 3000 - ...
[2026-09-28T19:03:07.140Z] "POST /notify HTTP/1.1" 500 FI - "-" ...
```

Two proxies, two flags, and they belong to different hops. `UT` — upstream
timeout — appears in the **client's** log against `booking-service`: that is the
3-second route timeout firing. `FI` — fault injected — appears in
**`booking-service`'s** log against `notification-service`: that is the fault
filter doing the holding. Looking for `UT` in `booking-service`'s log finds
nothing, because no timeout is configured on that hop.

---

## Step 8: Clean Up

A fault is configuration. It survives your terminal closing.

```sh
kubectl -n fault-demo delete virtualservice notification
```

---

## Common Mistakes

- **Fault on `booking-service` instead of `notification-service`.** Delays the inbound request; tests the wrong hop.
- **No header match, or the catch-all rule first.** Every caller gets the fault — a self-inflicted outage, and an automatic fail.
- **A fault or timeout left on the second rule.** Unmarked traffic is affected and the grader catches it.
- **Expecting a 500 at 7 seconds.** The 3-second timeout cuts the 7-second delay off first; you get a 504 at 3s.
- **Omitting `percentage` and assuming nothing happens.** The default is 100%.
- **Scoping on a header the intermediate service does not forward.** The fault silently never fires.
- **Reading only the outer response code.** In a two-hop chain, the interesting evidence is in the intermediate service's proxy log.
- **Leaving the fault in place afterwards.** Delete it.

---

---

## Reference

The official documentation for everything this task touches — open these rather than trying to recall field names:

- [VirtualService API](https://istio.io/latest/docs/reference/config/networking/virtual-service/) — the whole object: `hosts`, `gateways`, and every field an `http` rule can carry
- [Istio Kubernetes Gateway API task](https://istio.io/latest/docs/tasks/traffic-management/ingress/gateway-api/) — `GatewayClass`, `Gateway`, `HTTPRoute`, `parentRefs` and `allowedRoutes`
- [HTTPMatchRequest API](https://istio.io/latest/docs/reference/config/networking/virtual-service/#HTTPMatchRequest) — every match key: `headers`, `uri`, `queryParams`, `method`, `withoutHeaders`
- [StringMatch API](https://istio.io/latest/docs/reference/config/networking/virtual-service/#StringMatch) — the `exact` / `prefix` / `regex` choice and what each means
- [HTTPRoute API](https://istio.io/latest/docs/reference/config/networking/virtual-service/#HTTPRoute) — `timeout` alongside `retries`, `fault` and `mirror` on one rule
- [HTTPFaultInjection API](https://istio.io/latest/docs/reference/config/networking/virtual-service/#HTTPFaultInjection) — `delay`, `abort` and the percentage fields
- [Debugging Envoy and istiod](https://istio.io/latest/docs/ops/diagnostic-tools/proxy-cmd/) — `proxy-status`, `proxy-config` and `x describe` in full
- [Istio analyzer messages](https://istio.io/latest/docs/reference/config/analysis/) — every `IST####` code and what triggers it
