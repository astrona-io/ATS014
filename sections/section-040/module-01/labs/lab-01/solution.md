# Solution Walkthrough

One object with two rules that differ in exactly one respect — whether retrying is safe. The arithmetic in step 3 is what most people get wrong.

---

## Step 1: Establish the Unbounded Baseline

```sh
kubectl -n resilience-demo get virtualservice
kubectl -n resilience-demo exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code} %{time_total}s\n' http://httpbin:8000/delay/10
```

```text
No resources found in resilience-demo namespace.
200 10.021s
```

No timeout anywhere, so a ten-second response is a ten-second wait.

Now count what an unconfigured route does on failure — this is the implicit default policy in action:

```sh
BEFORE=$(kubectl -n resilience-demo logs deploy/httpbin -c istio-proxy --tail=-1 | grep -c /status/503)
kubectl -n resilience-demo exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code}\n' http://httpbin:8000/status/503
sleep 2
AFTER=$(kubectl -n resilience-demo logs deploy/httpbin -c istio-proxy --tail=-1 | grep -c /status/503)
echo "attempts: $((AFTER - BEFORE))"
```

```text
503
attempts: 1
```

One, because a `503` from the application is not in the default policy's list (`connect-failure`, `refused-stream`, `unavailable`, `cancelled`). That is worth seeing before you assume "no config" means "no retries" — for a *connection* failure the same route would retry twice.

---

## Step 2: Do the Budget Arithmetic First

The read rule needs `attempts: 3` and `perTryTimeout: 1s`. Before writing anything:

```text
attempts: 3   →  3 retries + 1 original try  =  4 attempts
4 attempts × 1s perTryTimeout                =  4s minimum
plus headroom for connection setup           →  use 5s
```

`timeout: 5s` it is. Picking `3s` here is the classic failure: the object applies cleanly, `istioctl analyze` is happy, and the fourth attempt never runs.

---

## Step 3: Write Both Rules, POST First

Write the manifest to a file and apply the file. It is the habit the exam rewards — you get something you can re-read, edit and re-apply, instead of a heredoc that is gone the moment it runs.

```sh
cat > virtualservice-httpbin.yaml <<'EOF'
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: httpbin
  namespace: resilience-demo
spec:
  hosts:
    - httpbin
  http:
    - match:
        - method:
            exact: POST
      route:
        - destination:
            host: httpbin
            port:
              number: 8000
      timeout: 3s
      retries:
        attempts: 0
    - route:
        - destination:
            host: httpbin
            port:
              number: 8000
      timeout: 5s
      retries:
        attempts: 3
        perTryTimeout: 1s
        retryOn: gateway-error
EOF
kubectl apply -f virtualservice-httpbin.yaml
istioctl analyze -n resilience-demo
```

```text
virtualservice.networking.istio.io/httpbin created
✔ No validation issues found when analyzing namespace: resilience-demo.
```

Three things worth naming:

- **The `POST` rule is first.** The read rule has no `match`, so it matches everything; below it, the `POST` rule would be unreachable.
- **`attempts: 0`, not an omitted `retries` block.** Omitting it leaves Istio's implicit default of 2 attempts on connection-level failures in force. Only the explicit zero means "never retry this".
- **`retryOn: gateway-error`**, which covers 502/503/504 — infrastructure-shaped failures. `5xx` would also retry a `500`, which is usually an application bug that will fail identically next time.

---

## Step 4: Confirm the Proxy Holds Both Policies

```sh
istioctl proxy-config routes deploy/tester -n resilience-demo -o json \
  | grep -E '"timeout"|retryOn|numRetries|perTryTimeout'
```

```text
"timeout": "3s",
"numRetries": 0,
"timeout": "5s",
"retryOn": "gateway-error",
"numRetries": 3,
"perTryTimeout": "1s",
```

Two routes, two policies. `numRetries` is Envoy's name for `attempts`, and seeing `3` beside `perTryTimeout: 1s` and `timeout: 5s` is the arithmetic checking out at a glance.

---

## Step 5: Verify the Read Path Retries

```sh
BEFORE=$(kubectl -n resilience-demo logs deploy/httpbin -c istio-proxy --tail=-1 | grep -c /status/503)
kubectl -n resilience-demo exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code}\n' http://httpbin:8000/status/503
sleep 3
AFTER=$(kubectl -n resilience-demo logs deploy/httpbin -c istio-proxy --tail=-1 | grep -c /status/503)
echo "attempts: $((AFTER - BEFORE))"
```

```text
503
attempts: 4
```

Four requests at the server for one client call. The caller still got a `503` — `/status/503` fails every time, and retries only help with transient failures.

---

## Step 6: Verify the Write Path Does Not

```sh
BEFORE=$(kubectl -n resilience-demo logs deploy/httpbin -c istio-proxy --tail=-1 | grep -c /status/503)
kubectl -n resilience-demo exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code}\n' -X POST http://httpbin:8000/status/503
sleep 3
AFTER=$(kubectl -n resilience-demo logs deploy/httpbin -c istio-proxy --tail=-1 | grep -c /status/503)
echo "attempts: $((AFTER - BEFORE))"
```

```text
503
attempts: 1
```

Exactly one. Same path, same status, different method — and a completely different policy, because the method match put it on the first rule.

---

## Step 7: Verify the Timeout Fires

```sh
kubectl -n resilience-demo exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code} %{time_total}s\n' http://httpbin:8000/delay/10
kubectl -n resilience-demo logs deploy/tester -c istio-proxy --tail=2
```

```text
504 5.011s
[2026-09-27T11:02:44.118Z] "GET /delay/10 HTTP/1.1" 504 UT upstream_response_timeout ...
```

`5.011s` — the full budget, not a truncated one. If you had set `timeout: 3s` this would read `504 3.0s` and the fourth attempt would never have run, which is the mistake the grader checks for.

`UT` in the access log confirms the caller's own proxy produced the 504 as a deadline, rather than the upstream returning one.

---

## Common Mistakes

- **`timeout: 3s` on the read rule.** Shorter than `(3 + 1) × 1s`; the retries are truncated and you get a 504 instead of four attempts.
- **Omitting the `retries` block on the POST rule.** Istio's implicit default still retries connection-level failures. Use `attempts: 0`.
- **Putting the catch-all rule first.** It matches everything, and the POST rule never runs.
- **Reading `attempts: 3` as three requests.** It is three retries — four attempts.
- **`retryOn: 5xx` instead of `gateway-error`.** Both would pass the attempt count here, but the task names `gateway-error`, and it is the better habit toward a service you might also be pool-limiting.
- **Counting server attempts without a baseline.** The log accumulates across runs; take a `BEFORE` count.
- **Checking the caller's output to count retries.** The caller sees one response no matter how many attempts happened. The server's proxy log is the evidence.

---

---

## Reference

The official documentation for everything this task touches — open these rather than trying to recall field names:

- [VirtualService API](https://istio.io/latest/docs/reference/config/networking/virtual-service/) — the whole object: `hosts`, `gateways`, and every field an `http` rule can carry
- [Istio Kubernetes Gateway API task](https://istio.io/latest/docs/tasks/traffic-management/ingress/gateway-api/) — `GatewayClass`, `Gateway`, `HTTPRoute`, `parentRefs` and `allowedRoutes`
- [HTTPMatchRequest API](https://istio.io/latest/docs/reference/config/networking/virtual-service/#HTTPMatchRequest) — every match key: `headers`, `uri`, `queryParams`, `method`, `withoutHeaders`
- [StringMatch API](https://istio.io/latest/docs/reference/config/networking/virtual-service/#StringMatch) — the `exact` / `prefix` / `regex` choice and what each means
- [HTTPRoute API](https://istio.io/latest/docs/reference/config/networking/virtual-service/#HTTPRoute) — `timeout` alongside `retries`, `fault` and `mirror` on one rule
- [HTTPRetry API](https://istio.io/latest/docs/reference/config/networking/virtual-service/#HTTPRetry) — `attempts`, `perTryTimeout`, `retryOn` and `retriableStatusCodes`
- [Debugging Envoy and istiod](https://istio.io/latest/docs/ops/diagnostic-tools/proxy-cmd/) — `proxy-status`, `proxy-config` and `x describe` in full
- [Istio analyzer messages](https://istio.io/latest/docs/reference/config/analysis/) — every `IST####` code and what triggers it
