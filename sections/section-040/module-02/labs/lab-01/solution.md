# Solution Walkthrough

Astronaut, here is the mission debrief. One small object raises the shields. The work is in the verification, because the whole point of this module is that a plausible-looking test proves nothing.

---

## Step 1: Establish the Unbounded Baseline

```sh
kubectl -n circuit-demo get destinationrule
kubectl -n circuit-demo exec deploy/fortio -c fortio -- \
  fortio load -c 5 -qps 0 -n 50 -loglevel Warning http://notification-service/notify 2>&1 | grep 'Code '
```

```text
No resources found in circuit-demo namespace.
Code 200 : 50 (100.0 %)
```

Fifty requests, five at a time, all successful. Nothing is capping concurrency.

---

## Step 2: Apply the Connection Pool

Write the manifest to a file and apply the file. It is the habit the exam rewards — you get something you can re-read, edit and re-apply, instead of a heredoc that is gone the moment it runs.

```sh
cat > destinationrule-notification-service.yaml <<'EOF'
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: notification-service
  namespace: circuit-demo
spec:
  host: notification-service
  trafficPolicy:
    connectionPool:
      tcp:
        maxConnections: 1
      http:
        http1MaxPendingRequests: 1
        maxRequestsPerConnection: 1
EOF
kubectl apply -f destinationrule-notification-service.yaml
```

```text
destinationrule.networking.istio.io/notification-service created
```

Note the two-level nesting: `tcp` and `http` are separate groups under `connectionPool`, and `maxConnections` belongs to `tcp` while the other two belong to `http`. Putting `maxConnections` under `http` is a schema error, which at least tells you immediately.

Do **not** add a `VirtualService`. A retry policy would re-send the rejected requests and mask the very behaviour you are demonstrating — the grader checks none exists.

---

## Step 3: Confirm the Limits Reached the Proxy

```sh
istioctl proxy-config cluster deploy/fortio -n circuit-demo \
  --fqdn notification-service.circuit-demo.svc.cluster.local -o json | grep -A8 circuitBreakers
```

```text
"circuitBreakers": {
  "thresholds": [
    {
      "maxConnections": 1,
      "maxPendingRequests": 1,
      "maxRequests": 4294967295,
      "maxRetries": 4294967295
```

Your two settings, plus two unset fields at `2^32 - 1` — unbounded. `maxRequests` is `http2MaxRequests`; it does not bind on HTTP/1 traffic, which is why the HTTP/1 breaker is built from the first two.

---

## Step 4: Prove the Limit Is on Concurrency, Not Volume

This is the step that distinguishes understanding from guessing. Same total request count, different concurrency:

```sh
kubectl -n circuit-demo exec deploy/fortio -c fortio -- \
  fortio load -c 1 -qps 0 -n 20 -loglevel Warning http://notification-service/notify 2>&1 | grep 'Code '
```

```text
Code 200 : 20 (100.0 %)
```

Twenty requests through a pool of one connection, all successful — because at `-c 1` there was never more than one in flight. A thousand would also succeed. If you stopped here you would wrongly conclude the policy did nothing.

Now raise the concurrency:

```sh
kubectl -n circuit-demo exec deploy/fortio -c fortio -- \
  fortio load -c 5 -qps 0 -n 50 -loglevel Warning http://notification-service/notify 2>&1 | grep 'Code '
```

```text
Code 200 : 31 (62.0 %)
Code 503 : 19 (38.0 %)
```

Your split will differ — on a fast local cluster requests complete quickly enough that many still get through. Note the run took roughly the same wall-clock time as the successful one: rejection is immediate, not a delay.

---

## Step 5: Prove the 503s Are the Breaker

Two independent pieces of evidence, plus one absence.

**The `UO` flag** in the caller's access log:

```sh
kubectl -n circuit-demo logs deploy/fortio -c istio-proxy --tail=50 | grep ' 503 UO ' | head -2
```

```text
[2026-09-27T11:41:09.882Z] "GET /notify HTTP/1.1" 503 UO upstream_reset_before_response_started{overflow} - "-" 0 81 0 - ...
```

`UO` is upstream overflow. An application 503 carries no flag.

**The counter**:

```sh
kubectl -n circuit-demo exec deploy/fortio -c istio-proxy -- \
  pilot-agent request GET stats | grep notification-service | grep -E 'pending_overflow|cx_overflow'
```

```text
cluster.outbound|80||notification-service...upstream_cx_overflow: 6
cluster.outbound|80||notification-service...upstream_rq_pending_overflow: 19
```

Nineteen requests rejected for lack of a pending slot. `upstream_rq_pending_overflow` is the counter to name if you are asked how to prove a breaker tripped.

**The absence** at the backend:

```sh
kubectl -n circuit-demo logs -l app=notification-service -c istio-proxy --tail=100 | grep -c ' 503 '
```

```text
0
```

Zero. The backend never heard about any of them, because the caller's proxy rejected them before they left. That asymmetry is the strongest single proof of where the limit lives.

---

## Common Mistakes

- **Testing with `-c 1`.** Sequential load never trips a concurrency limit, however many requests you send.
- **Adding a `VirtualService` with retries.** The retries re-send the rejected requests and the failure rate appears to improve, while the real load goes up. The grader rejects it.
- **Putting `maxConnections` under `http`.** It belongs under `tcp`.
- **Looking for the 503s in the backend's logs.** They are not there and never will be.
- **Concluding "no breaker" because the counters are zero.** If `pending_overflow` and `cx_overflow` are both flat while you are seeing 503s, the cause is elsewhere — that is useful information, not a failed test.
- **Expecting the limit to protect the service globally.** Each client enforces its own pool; the backend's exposure is `limit × number of callers`.
- **Forgetting `http2MaxRequests` for gRPC.** On HTTP/2 one connection carries many streams, so `maxConnections` barely constrains anything.
