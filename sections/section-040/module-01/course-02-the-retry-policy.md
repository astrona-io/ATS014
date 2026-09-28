# The Retry Policy

> Prerequisite: [The Route Timeout](./course-01-the-route-timeout.md). Next: [The Shared Budget And Idempotency](./course-03-the-shared-budget-and-idempotency.md).

Retries are already happening in your mesh whether or not you have configured them. This part covers the three fields that control them, the off-by-one in the most important one, and the default policy that explains a class of "why did that take so long" questions.

## The three fields

```yaml
http:
  - route:
      - destination:
          host: httpbin
          port:
            number: 8000
    retries:
      attempts: 3
      perTryTimeout: 1s
      retryOn: 5xx,connect-failure
```

- **`attempts`** — how many **retries** happen after the first try fails. `attempts: 3` means up to **four** requests reach the upstream in total.
- **`perTryTimeout`** — the deadline for each individual attempt.
- **`retryOn`** — a comma-separated list of conditions that make a failed attempt retriable.

The `attempts` off-by-one is worth fixing in memory now, because it is easy to misread under time pressure and because Envoy's own name for the field — `numRetries` — says it more clearly than Istio's does. When a task says "three attempts", decide whether it means three requests (`attempts: 2`) or three retries (`attempts: 3`), and prefer the reading that matches the budget arithmetic in Part 3.

## What `retryOn` accepts

| Condition | Retries when |
| --- | --- |
| `5xx` | the upstream answered with any 5xx status |
| `gateway-error` | narrower: 502, 503 and 504 only |
| `connect-failure` | the connection could not be established |
| `refused-stream` | the upstream sent an HTTP/2 `REFUSED_STREAM` |
| `reset` | the upstream reset the connection before responding |
| `retriable-status-codes` | the status appears in a `retriableStatusCodes` list you supply |
| `retriable-headers` | the response carries a header you listed in `retriableRequestHeaders` |

Note what is absent: **4xx**. A `400` or `404` is the client's problem, and retrying produces the same answer more slowly. `retryOn: 5xx` will not touch them, by design. If you genuinely need a specific non-5xx code retried, that is what `retriable-status-codes` is for:

```yaml
retries:
  attempts: 2
  retryOn: retriable-status-codes
  retriableStatusCodes:
    - 418
```

`gateway-error` versus `5xx` is a real choice rather than a stylistic one. `5xx` includes `500` — an application error, which is usually deterministic and will fail identically on retry. `gateway-error` covers only the codes that suggest an infrastructure problem worth retrying. On a route to a service you are also connection-pool limiting (module 2), `gateway-error` is the safer default, because a pool rejection is a `503` and retrying it makes the overload worse.

## Watching retries happen

The caller cannot see retries — it gets one response. The evidence is on the **server** side, where each attempt arrives as a separate request.

> [!TIP]
> **Try it — count the attempts that actually reach the server**
>
> ```sh
> kubectl -n resilience-demo patch virtualservice httpbin --type merge -p '
> spec:
>   http:
>     - route:
>         - destination:
>             host: httpbin
>             port:
>               number: 8000
>       timeout: 5s
>       retries:
>         attempts: 3
>         perTryTimeout: 1s
>         retryOn: 5xx,connect-failure'
> BEFORE=$(kubectl -n resilience-demo logs deploy/httpbin -c istio-proxy --tail=-1 2>/dev/null | grep -c '/status/503')
> kubectl -n resilience-demo exec deploy/tester -- \
>   curl -s -o /dev/null -w '%{http_code}\n' http://httpbin:8000/status/503
> sleep 2
> AFTER=$(kubectl -n resilience-demo logs deploy/httpbin -c istio-proxy --tail=-1 2>/dev/null | grep -c '/status/503')
> echo "attempts reaching the server: $((AFTER - BEFORE))"
> ```
>
> Expect something like:
>
> ```text
> 503
> attempts reaching the server: 4
> ```
>
> One client request, four requests logged by the server's proxy: the original attempt plus three retries. The caller still got a `503`, because `/status/503` fails every time — retries help with *transient* failures, and this one is permanent by construction.

That last sentence is the honest framing for retries generally. They convert a flaky dependency into a reliable one; they do nothing for a broken one except multiply the load on it.

## The default policy nobody configured

Every route with no `retries` block still has a retry policy: **2 attempts**, on `connect-failure`, `refused-stream`, `unavailable` and `cancelled`.

It is usually on your side — it absorbs the brief connection failures that happen when a pod is rescheduled or a node drains, and it is a large part of why a rolling update looks seamless. But it explains two things people find mysterious:

- **A failing request sometimes takes longer than expected.** It was retried, twice, before you were told.
- **Removing the `retries` block does not disable retries.** Nor does `retries: {}`.

To genuinely switch them off you must say so:

```yaml
retries:
  attempts: 0
```

> [!TIP]
> **Try it — prove the implicit default exists**
>
> ```sh
> kubectl -n resilience-demo patch virtualservice httpbin --type merge -p '
> spec:
>   http:
>     - route:
>         - destination:
>             host: httpbin
>             port:
>               number: 8000
>       timeout: 5s
>       retries:
>         attempts: 0'
> BEFORE=$(kubectl -n resilience-demo logs deploy/httpbin -c istio-proxy --tail=-1 2>/dev/null | grep -c '/status/503')
> kubectl -n resilience-demo exec deploy/tester -- \
>   curl -s -o /dev/null -w '%{http_code}\n' http://httpbin:8000/status/503
> sleep 2
> AFTER=$(kubectl -n resilience-demo logs deploy/httpbin -c istio-proxy --tail=-1 2>/dev/null | grep -c '/status/503')
> echo "attempts reaching the server: $((AFTER - BEFORE))"
> ```
>
> Expect something like:
>
> ```text
> 503
> attempts reaching the server: 1
> ```
>
> Exactly one. Compare with the four from the previous checkpoint and with what you would get from a route carrying no `retries` block at all — the latter would show retries for connection-level failures even though you wrote nothing. `attempts: 0` is the only way to mean "do not retry".

> *`attempts` counts retries after the first try, and a route with no `retries` block still retries twice on connection-level failures.*

## Reference

- [HTTPRetry API](https://istio.io/latest/docs/reference/config/networking/virtual-service/#HTTPRetry) — `attempts`, `perTryTimeout`, `retryOn`, `retriableStatusCodes` and `retryRemoteLocalities`.
- [Envoy retry semantics](https://www.envoyproxy.io/docs/envoy/latest/configuration/http/http_filters/router_filter#x-envoy-retry-on) — the authoritative meaning of every `retryOn` token.
- [Global mesh retry defaults](https://istio.io/latest/docs/reference/config/istio.mesh.v1alpha1/#MeshConfig) — where the implicit default policy is defined and how to change it mesh-wide.
- `istioctl proxy-config routes -o json` — where `numRetries` and `retryOn` are visible on the live route.
