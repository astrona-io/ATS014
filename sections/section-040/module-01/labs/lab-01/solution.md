# Solution Walkthrough

You build one `VirtualService` with two rules. A `VirtualService` is the Istio object that sets how requests to a host are routed, including timeouts and retries. The two rules differ in one point: whether it is safe to send the request again. The walkthrough builds the file in two steps. Items 1 to 4 write the `POST` rule. Items 5 to 8 write the read rule, and item 8 needs arithmetic. Items 9 to 13 prove the result with the configuration of the proxy and with real requests.

---

## Start: Look At The Starting State

The task says that no `VirtualService` exists, so there is no route timeout. Check that this is true, and time a request that takes 3 seconds from the `tester` pod. `/delay/<seconds>` waits before it answers:

```sh
kubectl -n resilience-demo get virtualservice
kubectl -n resilience-demo get pods
kubectl -n resilience-demo exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code} %{time_total}s\n' http://httpbin:8000/delay/3
```

```text
No resources found in resilience-demo namespace.
NAME                       READY   STATUS    RESTARTS   AGE
httpbin-549d87477d-bvl7j   2/2     Running   0          6s
tester-69699fd775-zrr9j    2/2     Running   0          6s
200 3.019510s
```

There is no timeout, so the request waits the full 3 seconds. Now see what a route without any configuration does with a failing request. The proof is on the server side. The sidecar proxy of `httpbin` is the Envoy container that Istio adds to the pod, and it writes one access log line for each request it receives. Count the lines for `/status/503` before and after one request. Wait before each count, because the proxy writes the line a moment after the request:

```sh
sleep 5
BEFORE=$(kubectl -n resilience-demo logs deploy/httpbin -c istio-proxy --tail=-1 | grep -c /status/503)
kubectl -n resilience-demo exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code}\n' http://httpbin:8000/status/503
sleep 5
AFTER=$(kubectl -n resilience-demo logs deploy/httpbin -c istio-proxy --tail=-1 | grep -c /status/503)
echo "attempts: $((AFTER - BEFORE))"
```

```text
503
attempts: 1
```

One request reached the server. A `503` from the application is not in the default retry list of Istio, which covers connection failures. So "no configuration" does not mean "no retries": for a connection failure, the same route would retry twice. I use this count method in the items below.

---

## Items 1 To 4: The Write Path

> **Task item 1:** Matches requests whose method is **`POST`**.
>
> **Task item 2:** Routes to `httpbin` on port 8000.
>
> **Task item 3:** Sets `timeout` to **`3s`**.
>
> **Task item 4:** **Switches retries off.** A retried `POST` repeats whatever the first one did, so exactly one request must reach the server per client call. Leaving the `retries` block out does *not* do this.

The four items describe the first rule. The proxy reads the rules from top to bottom and uses the first one that matches. A rule without `match` matches every request. So the `POST` rule must be first. Write `retries` with `attempts: 0`. Without the block, Istio still retries connection failures by default. Only an explicit zero means "never retry".

For now, add a plain second rule, so that other requests still have a route. Save this as `virtualservice-httpbin.yaml`:

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
```

Apply it:

```sh
kubectl apply -f virtualservice-httpbin.yaml
```

```text
virtualservice.networking.istio.io/httpbin created
```

Check items 1 to 4. Print the first rule, and then send a `POST` to `/status/503` and count the requests at the server:

```sh
kubectl -n resilience-demo get virtualservice httpbin -o jsonpath='{.spec.http[0]}{"\n"}'
sleep 5
BEFORE=$(kubectl -n resilience-demo logs deploy/httpbin -c istio-proxy --tail=-1 | grep -c /status/503)
kubectl -n resilience-demo exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code}\n' -X POST http://httpbin:8000/status/503
sleep 5
AFTER=$(kubectl -n resilience-demo logs deploy/httpbin -c istio-proxy --tail=-1 | grep -c /status/503)
echo "attempts: $((AFTER - BEFORE))"
```

```text
{"match":[{"method":{"exact":"POST"}}],"retries":{"attempts":0},"route":[{"destination":{"host":"httpbin","port":{"number":8000}}}],"timeout":"3s"}
503
attempts: 1
```

The rule matches the method `POST`, routes to `httpbin` on port 8000, has `timeout` `3s`, and has `retries` with `attempts: 0`. One request reached the server for one client call.

---

## Items 5 To 8: The Read Path

> **Task item 5:** Has no `match` block. It is the catch-all rule, so it must come second.
>
> **Task item 6:** Routes to `httpbin` on port 8000.
>
> **Task item 7:** Retries with **`attempts: 3`**, **`perTryTimeout: 1s`**, and `retryOn` set to **`gateway-error`**.
>
> **Task item 8:** Sets a `timeout` large enough that all four tries can run. Work it out rather than guessing: `attempts` counts retries *after* the first try, and the route timeout covers every try together. A timeout that cuts the retries short fails this task.

Do the arithmetic before you write anything:

```text
attempts: 3   ->  3 retries + 1 original try  =  4 tries
4 tries x 1s perTryTimeout                    =  4s minimum
plus headroom for connection setup            ->  use 5s
```

So the read rule gets `timeout: 5s`. A timeout of `3s` is the classic mistake. The object applies cleanly, `istioctl analyze` reports no problem, and the fourth try never runs.

`retryOn: gateway-error` covers the status codes 502, 503 and 504, which come from the network or from a proxy. `5xx` would also retry a `500`, which is usually an application bug that fails the same way on the next try. Replace the second rule in `virtualservice-httpbin.yaml`:

```yaml
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

The whole file now has the `POST` rule first and this rule second. Apply it:

```sh
kubectl apply -f virtualservice-httpbin.yaml
```

```text
virtualservice.networking.istio.io/httpbin configured
```

Check items 5 to 8. Print the second rule, and let Istio check the objects:

```sh
kubectl -n resilience-demo get virtualservice httpbin -o jsonpath='{.spec.http[1]}{"\n"}'
istioctl analyze -n resilience-demo
```

```text
{"retries":{"attempts":3,"perTryTimeout":"1s","retryOn":"gateway-error"},"route":[{"destination":{"host":"httpbin","port":{"number":8000}}}],"timeout":"5s"}

✔ No validation issues found when analyzing namespace: resilience-demo.
```

The second rule has no `match`, routes to `httpbin` on port 8000, retries 3 times with a per-try timeout of `1s` on `gateway-error`, and has `timeout` `5s`.

---

## Item 9: The Proxy Holds The Retry Policy

> **Task item 9:** The `tester` sidecar proxy holds the retry policy (`numRetries` appears in its route configuration).

`istioctl proxy-config routes` prints the routes that `istiod`, the Istio control plane, has sent to one proxy. Read the route table for port 8000 of the `tester` proxy:

```sh
istioctl proxy-config routes deploy/tester -n resilience-demo --name 8000 -o json \
  | grep -E '"timeout"|retryOn|numRetries|perTryTimeout'
```

```text
                            "timeout": "3s",
                            "timeout": "5s",
                                "retryOn": "gateway-error",
                                "numRetries": 3,
                                "perTryTimeout": "1s",
                            "timeout": "0s",
```

The first entry is the `POST` rule: a `3s` timeout, and no retry fields at all, because retries are off. The next entries are the read rule: `5s`, `gateway-error`, `numRetries` 3 and `perTryTimeout` `1s`. `numRetries` is the name that Envoy uses for `attempts`. If the output does not show your values, wait a few seconds for `istiod` to send the change, and run the command again.

---

## Item 10: A Read Is Tried Four Times

> **Task item 10:** A `GET http://httpbin:8000/status/503` produces **4** requests at the server: the first try plus three retries.

```sh
sleep 5
BEFORE=$(kubectl -n resilience-demo logs deploy/httpbin -c istio-proxy --tail=-1 | grep -c /status/503)
kubectl -n resilience-demo exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code}\n' http://httpbin:8000/status/503
sleep 5
AFTER=$(kubectl -n resilience-demo logs deploy/httpbin -c istio-proxy --tail=-1 | grep -c /status/503)
echo "attempts: $((AFTER - BEFORE))"
```

```text
503
attempts: 4
```

Four requests reached the server for one client call. The client still got a `503`, because `/status/503` fails every time. Retries help only with short failures.

---

## Item 11: A Write Is Tried Once

> **Task item 11:** A `POST http://httpbin:8000/status/503` produces exactly **1** request at the server.

```sh
sleep 5
BEFORE=$(kubectl -n resilience-demo logs deploy/httpbin -c istio-proxy --tail=-1 | grep -c /status/503)
kubectl -n resilience-demo exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code}\n' -X POST http://httpbin:8000/status/503
sleep 5
AFTER=$(kubectl -n resilience-demo logs deploy/httpbin -c istio-proxy --tail=-1 | grep -c /status/503)
echo "attempts: $((AFTER - BEFORE))"
```

```text
503
attempts: 1
```

Exactly one request reached the server. The path and the status code are the same as in item 10. Only the method differs, and the method match sent the request to the first rule.

---

## Item 12: The Timeout Fires And Returns 504

> **Task item 12:** A `GET http://httpbin:8000/delay/10` returns **504**, and takes about as long as the read timeout you configured. This proves that the timeout fires, and that the retries are not cut short earlier.

Send a request that takes 10 seconds, and read the last line of the access log of the `tester` proxy:

```sh
kubectl -n resilience-demo exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code} %{time_total}s\n' http://httpbin:8000/delay/10
sleep 2
kubectl -n resilience-demo logs deploy/tester -c istio-proxy --tail=1
```

```text
504 4.092026s
[2026-10-20T20:55:20.195Z] "GET /delay/10 HTTP/1.1" 504 URX,UT upstream_per_try_timeout - "-" 0 24 4087 - "-" "curl/8.23.0" "000de922-2311-9bf8-a45b-f9a59415b02b" "httpbin:8000" "10.244.0.8:8080" outbound|8000||httpbin.resilience-demo.svc.cluster.local 10.244.0.9:54232 10.96.50.95:8000 10.244.0.9:57620 - -
```

The client got a `504` after about 4.1 seconds. That fits the arithmetic: four tries of `1s` each. The response flags are `URX` ("retry limit exceeded") and `UT` ("upstream timeout"). The proxy of the client created the `504`, and the server did not return it. The route timeout of `5s` did not fire first, because the four tries ended at 4 seconds. A route timeout of `3s` would have cut the tries short at 3 seconds, and the fourth try would never have run.

---

## Item 13: The Timeout Is Large Enough

> **Task item 13:** The read rule's `timeout` is at least `(attempts + 1) × perTryTimeout`.

Print the three values of the read rule:

```sh
kubectl -n resilience-demo get virtualservice httpbin \
  -o jsonpath='timeout={.spec.http[1].timeout} attempts={.spec.http[1].retries.attempts} perTry={.spec.http[1].retries.perTryTimeout}{"\n"}'
```

```text
timeout=5s attempts=3 perTry=1s
```

The formula gives `(3 + 1) × 1s = 4s`, and the timeout is `5s`, which is at least `4s`.

---

## Submit

Send the lab for grading:

```sh
astrona submit -c sections/section-040/module-01/labs/lab-01
```

The grader counts the requests at the server and times the slow request.

---

## Mistakes That Fail The Grader

- **`timeout: 3s` on the read rule (item 8).** It is shorter than `(3 + 1) × 1s`, so the timeout cuts the retries short.
- **Leaving out the `retries` block on the `POST` rule (item 4).** The default policy of Istio still retries connection failures. Use `attempts: 0`.
- **Putting the catch-all rule first (items 1 and 5).** It matches everything, and the `POST` rule is never used.
- **Reading `attempts: 3` as three requests (item 7).** It means three retries, so four tries in total.
- **`retryOn: 5xx` instead of `gateway-error` (item 7).** The count of requests looks the same, but the task asks for `gateway-error`, and `5xx` also retries application errors such as `500`.
- **Counting server requests without a count before the test (items 10 and 11).** The log grows across runs. Take a count first, and wait before each count.
- **Counting retries from the client output (items 10 and 11).** The client gets one response however many tries happened. The access log of the server is the proof.
