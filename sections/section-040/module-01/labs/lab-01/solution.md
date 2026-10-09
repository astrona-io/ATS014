# Solution Walkthrough

The answer is one `VirtualService` with two rules. A `VirtualService` is the Istio object that sets how requests to a host are routed, including timeouts and retries. The two rules differ in one point: whether it is safe to send the request again. The arithmetic in step 2 is what most people get wrong.

---

## Step 1: Look at the Starting State

Check that there is no `VirtualService`, and time a slow request from the `tester` pod:

```sh
kubectl -n resilience-demo get virtualservice
kubectl -n resilience-demo exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code} %{time_total}s\n' http://httpbin:8000/delay/10
```

```text
No resources found in resilience-demo namespace.
200 10.021s
```

There is no timeout anywhere, so a ten-second response means a ten-second wait.

Now count what a route without configuration does on a failure. This shows Istio's default retry policy at work. The count comes from the access log of the `httpbin` sidecar proxy, the Envoy container that writes one line per request it receives. `BEFORE` and `AFTER` hold the number of matching lines before and after the request:

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

The result is one request. A `503` from the application is not in the default policy's list (`connect-failure`, `refused-stream`, `unavailable`, `cancelled`). So "no configuration" does not mean "no retries": for a *connection* failure, the same route would retry twice.

---

## Step 2: Work Out the Timeout First

The read rule needs `attempts: 3` and `perTryTimeout: 1s`. Before you write anything, do the arithmetic:

```text
attempts: 3   →  3 retries + 1 original try  =  4 attempts
4 attempts × 1s perTryTimeout                =  4s minimum
plus headroom for connection setup           →  use 5s
```

So the read rule gets `timeout: 5s`. Picking `3s` here is the classic mistake: the object applies cleanly, `istioctl analyze` reports no problem, and the fourth try never runs.

---

## Step 3: Write Both Rules, POST First

Save this as `virtualservice-httpbin.yaml`:

```yaml
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
```

Apply it:

```sh
kubectl apply -f virtualservice-httpbin.yaml
```

Then check the result:

```sh
istioctl analyze -n resilience-demo
```

```text
virtualservice.networking.istio.io/httpbin created
✔ No validation issues found when analyzing namespace: resilience-demo.
```

Three choices in this file matter:

- **The `POST` rule is first.** The sidecar proxy checks the rules from the top and uses the first one that matches. The read rule has no `match`, so it matches everything. Below it, the `POST` rule would never be used.
- **`attempts: 0`, not a missing `retries` block.** Without the block, Istio's default policy of 2 retries on connection failures still applies. Only an explicit zero means "never retry".
- **`retryOn: gateway-error`.** It covers 502, 503 and 504, failures caused by the network or a proxy. `5xx` would also retry a `500`, which is usually an application bug that fails the same way on the next try.

---

## Step 4: Confirm the Proxy Holds Both Policies

`istioctl proxy-config routes` prints the routes that `istiod`, the Istio control plane, has sent to one sidecar proxy. Read the timeout and retry fields in the `tester` route table:

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

There are two routes with two policies. `numRetries` is Envoy's name for `attempts`. With `3` next to `perTryTimeout: 1s` and `timeout: 5s`, you can check the arithmetic at a glance.

---

## Step 5: Check That the Read Path Retries

Send one `GET` to `/status/503` and count the requests at the server:

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

Four requests reached the server for one client call. The client still got a `503`, because `/status/503` fails every time. Retries only help with short failures.

---

## Step 6: Check That the Write Path Does Not Retry

Send the same request as a `POST`:

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

Exactly one request reached the server. The path and the status code are the same, but the method is different. The method match sent the request to the first rule, which has retries switched off.

---

## Step 7: Check That the Timeout Fires

Send a request that takes ten seconds, and read the `tester` access log:

```sh
kubectl -n resilience-demo exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code} %{time_total}s\n' http://httpbin:8000/delay/10
kubectl -n resilience-demo logs deploy/tester -c istio-proxy --tail=2
```

You should see (log line shortened):

```text
504 5.011s
[2026-09-27T11:02:44.118Z] "GET /delay/10 HTTP/1.1" 504 UT upstream_response_timeout ...
```

The request stopped after `5.011s`, the full read timeout. If you had set `timeout: 3s`, this would read about `504 3.0s`, and the fourth try would never have run. The grader checks for that mistake.

The response flag `UT` ("upstream timeout") in the access log shows that the client's own sidecar proxy created the `504` when the timeout ran out. The server did not return it.

---

## Common Mistakes

- **`timeout: 3s` on the read rule.** It is shorter than `(3 + 1) × 1s`, so the timeout cuts the retries short and you get a `504` instead of four tries.
- **Leaving out the `retries` block on the `POST` rule.** Istio's default policy still retries connection failures. Use `attempts: 0`.
- **Putting the catch-all rule first.** It matches everything, and the `POST` rule is never used.
- **Reading `attempts: 3` as three requests.** It means three retries, so four tries in total.
- **`retryOn: 5xx` instead of `gateway-error`.** Both pass the request count here, but the grader checks for `gateway-error`, and it does not retry application errors such as `500`.
- **Counting server requests without a starting count.** The log grows across runs, so take a `BEFORE` count first.
- **Counting retries from the client's output.** The client gets one response however many tries happened. The server's access log is the proof.
