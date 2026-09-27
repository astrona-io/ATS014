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

## Step 2: Work Out What the Two Faults Will Actually Do

The task asks for a 7-second delay **and** a 500 abort **and** a 3-second timeout on the same rule. Think that through before applying it:

```text
  request matches rule 1
        │
        ▼
  delay: hold for 7s  ─────┐
        │                  │  but the route timeout is 3s
        ▼                  │
  abort: return 500        │  ← never reached
                           ▼
              at t=3s the timeout fires: 504
```

The delay runs first. The timeout cuts the request off at three seconds, which is before the seven-second hold completes — so the abort never gets its turn. The observable result is a **504 at about 3 seconds**, not a 500 at 7.

That is the point of the exercise: a fabricated delay is how you make a timeout fire on demand, reproducibly, without waiting for a real slow dependency.

---

## Step 3: Write Both Rules

```sh
kubectl apply -f - <<'EOF'
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
      timeout: 3s
      route:
        - destination:
            host: notification-service
    - route:
        - destination:
            host: notification-service
EOF
istioctl analyze -n fault-demo
```

```text
virtualservice.networking.istio.io/notification created
✔ No validation issues found when analyzing namespace: fault-demo.
```

Three things the grader checks specifically:

- **`hosts: [notification-service]`**, not `booking-service`. The fault belongs on the host you are pretending is broken. Putting it on `booking-service` would delay the inbound request from curl — a different experiment entirely.
- **The scoped rule is first.** The catch-all has no `match`, so it matches everything; below it, the header rule would be dead.
- **The second rule is clean** — no fault, no timeout. That is what keeps everyone else's traffic working.

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

Note which proxy that is: **`booking-service`**, the caller. The `VirtualService` is keyed by the callee's hostname, but the filter runs in the calling workload's sidecar.

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
kubectl -n fault-demo logs -l app=booking-service -c istio-proxy --tail=10 | grep -E ' 504 UT | FI '
```

```text
[2026-09-27T12:31:02.117Z] "POST /notify HTTP/1.1" 504 UT upstream_response_timeout - "-" 0 24 3001 - ...
```

`UT` — upstream timeout — in the **caller's** log, on the inner call to `notification-service`. That is the route timeout doing its job, driven by a delay you fabricated.

Worth noting for the exam: had the abort won instead, the flag would read **`FI`** (fault injected). The two flags tell you which half of the fault produced the result.

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
