# Part 1 — The Route Timeout

> Prerequisite: [the module landing page](./course.md). Next: [Part 2 — The Retry Policy](./course-02-the-retry-policy.md).

One field, and three properties worth being precise about: where it is measured, what the caller gets, and what it does not do. This part settles all three before retries complicate the picture.

## The unbounded default

There is **no route-level timeout by default**. A slow response is simply a long wait, and the mesh does not object.

> [!TIP]
> **Try it — a slow call with nothing bounding it**
>
> ```sh
> kubectl -n resilience-demo exec deploy/tester -- \
>   curl -s -o /dev/null -w '%{http_code} %{time_total}s\n' http://httpbin:8000/delay/1
> kubectl -n resilience-demo exec deploy/tester -- \
>   curl -s -o /dev/null -w '%{http_code} %{time_total}s\n' http://httpbin:8000/delay/10
> ```
>
> Expect something like:
>
> ```text
> 200 1.014s
> 200 10.021s
> ```
>
> Ten seconds, and the caller waited every one of them. That is the behaviour a deadline replaces — and note that in a real system those ten seconds are ten seconds of a connection, a thread and a request slot held open in *every* service between the user and this one.

## The field

`timeout` sits on the HTTP rule, alongside `route`. It is a duration string:

```yaml
http:
  - route:
      - destination:
          host: httpbin
          port:
            number: 8000
    timeout: 5s
```

Three properties, each with a consequence:

**It is measured by the client's proxy.** The deadline lives in the calling workload's sidecar, not on the server. So it protects the caller even if the upstream never responds at all — including when the upstream is wedged, unreachable, or has no endpoints.

**The caller receives HTTP 504.** When the deadline expires the sidecar synthesises a `504 Gateway Timeout` and returns it. The upstream never gets a chance to answer, and the response did not come from it.

**It covers the entire request as the caller experiences it.** Once retries exist, that means all attempts together — which is Part 3's subject. Hold the thought.

> [!TIP]
> **Try it — the same slow call under a 5-second deadline**
>
> ```sh
> kubectl apply -f - <<'EOF'
> apiVersion: networking.istio.io/v1
> kind: VirtualService
> metadata:
>   name: httpbin
>   namespace: resilience-demo
> spec:
>   hosts:
>     - httpbin
>   http:
>     - route:
>         - destination:
>             host: httpbin
>             port:
>               number: 8000
>       timeout: 5s
> EOF
> kubectl -n resilience-demo exec deploy/tester -- \
>   curl -s -o /dev/null -w '%{http_code} %{time_total}s\n' http://httpbin:8000/delay/10
> ```
>
> Expect something like:
>
> ```text
> 504 5.009s
> ```
>
> The caller gave up at five seconds with a 504 rather than waiting ten. Note the time is the *timeout*, not the delay — which is how you tell a fired deadline from a slow success.

## What a timeout does not do

Three clarifications that prevent a category of misunderstanding.

**It does not stop the upstream.** The `httpbin` pod is still sleeping out its ten seconds, and will finish the work and try to write a response to a connection the proxy has already abandoned. A timeout bounds *your waiting*, not the server's working. On a real service that means a timeout does not reduce load on an overloaded dependency — it just stops you queueing behind it.

**It is not a connection timeout.** `timeout` is the deadline for the whole HTTP exchange. Envoy has separate connection-level settings, and section 040's `connectionPool` has a `tcp.connectTimeout` for establishing the TCP connection. A route timeout of `5s` does not mean "give up if the connection takes more than 5s to establish" — it means the whole thing, connect included, must finish inside five seconds.

**It is not a guarantee of promptness.** A 504 at exactly the deadline is the well-behaved case. If the proxy itself is saturated the response may be later; the deadline bounds intent, not scheduler latency.

## Reading the result in the access log

The caller's status code tells you *that* a timeout fired. The access log tells you *the proxy did it*, which matters when you are distinguishing a synthesised 504 from one a gateway upstream produced.

Envoy stamps each access log line with **response flags** — short codes describing how the request ended. The one for a route timeout is `UT`, upstream timeout.

> [!TIP]
> **Try it — the `UT` flag in the caller's own log**
>
> ```sh
> kubectl -n resilience-demo exec deploy/tester -- \
>   curl -s -o /dev/null -w '%{http_code} %{time_total}s\n' http://httpbin:8000/delay/10
> kubectl -n resilience-demo logs deploy/tester -c istio-proxy --tail=2
> ```
>
> Expect something like:
>
> ```text
> 504 5.011s
> [2026-09-27T11:02:44.118Z] "GET /delay/10 HTTP/1.1" 504 UT upstream_response_timeout - "-" 0 24 5001 - "-" "curl/8.5.0" ... "httpbin:8000" ...
> ```
>
> `504 UT` and `upstream_response_timeout` in one line, in the **client's** proxy log. A 504 with no `UT` came from somewhere else and means something different — worth knowing before you debug the wrong hop.

Response flags recur throughout this section, so it is worth collecting them as you go:

| Flag | Meaning | Module |
| --- | --- | --- |
| `UT` | upstream timeout — a deadline fired | this one |
| `UO` | upstream overflow — a circuit breaker rejected it | module 2 |
| `UH` | no healthy upstream — every endpoint was ejected or absent | module 3 |
| `UF` | upstream connection failure | general |

> *A route timeout is measured by the caller's own proxy and produces a synthesised 504 — the upstream keeps working regardless.*

## Reference

- [Request timeouts task](https://istio.io/latest/docs/tasks/traffic-management/request-timeouts/) — the upstream walkthrough for this field.
- [HTTPRoute API](https://istio.io/latest/docs/reference/config/networking/virtual-service/#HTTPRoute) — `timeout` alongside `retries`, `fault` and `mirror` on the same rule.
- [Envoy response flags](https://www.envoyproxy.io/docs/envoy/latest/configuration/observability/access_log/usage#config-access-log-format-response-flags) — the full list, including `UT`, `UO` and `UH`.
- [Istio access logs](https://istio.io/latest/docs/tasks/observability/logs/access-log/) — enabling and reading them, if a cluster does not have them on.
