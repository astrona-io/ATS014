# Part 3 — Scoping, Composition And Hazards

> Prerequisite: [Part 2 — `fault.abort`](./course-02-fault-abort.md). Next: [the module landing page](./course.md).

Everything so far affects every caller of the host. In a shared cluster that is a self-inflicted outage. This part is about limiting the blast radius, using injection to drive the section 040 features, and finding a fault somebody left behind.

## Scoping a fault so it hurts only you

The fix uses matching you already know: put the fault on a rule that only your test requests match, and leave a normal rule below it for everyone else. Rules are evaluated top down and first match wins, so the scoped rule goes **first** and the plain route goes last.

```yaml
http:
  - match:
      - headers:
          end-user:
            exact: tester
    fault:
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
```

This is the shape to reach for by default. It makes fault injection something you can do in an environment other people are using, and it is a realistic exam scenario precisely because the unscoped version is irresponsible.

> [!TIP]
> **Try it — the fault applies only to the marked request**
>
> ```sh
> kubectl -n fault-demo patch virtualservice notification --type merge -p '
> spec:
>   http:
>     - match:
>         - headers:
>             end-user:
>               exact: tester
>       fault:
>         abort:
>           httpStatus: 500
>           percentage:
>             value: 100
>       route:
>         - destination:
>             host: notification-service
>     - route:
>         - destination:
>             host: notification-service'
> kubectl -n fault-demo run t3 --rm -i --restart=Never --image=curlimages/curl -- sh -c \
>   'curl -s -o /dev/null -w "with header: %{http_code}\n" -H "end-user: tester" -X POST http://booking-service/book;
>    curl -s -o /dev/null -w "no header:   %{http_code}\n" -X POST http://booking-service/book'
> ```
>
> Expect something like:
>
> ```text
> with header: 500
> no header:   200
> ```
>
> Note what had to happen for this to work: the `end-user` header set on the **inbound** request reached the second hop. `booking-service` forwards it. A service that does not propagate headers cannot be tested this way at all — which is one practical argument for header propagation in general, and a thing to check before blaming the fault configuration.

## Driving the section 040 features

This is what the module is for. Three experiments, each pointing at one field from the previous section:

| Experiment | Tests | What you should see |
| --- | --- | --- |
| `delay.fixedDelay: 7s` against `timeout: 3s` | the route timeout | `504` in about three seconds, every time, with `UT` in the log |
| `abort.httpStatus: 503` against a retry policy | retries | `attempts + 1` requests in the *caller's* log, all aborted; retries cannot help when every attempt is faulted |
| `abort` at 60% against `outlierDetection` | ejection thresholds | whether your `consecutive5xxErrors` is reachable at that failure rate |

The second one deserves a note, because the result surprises people. An injected abort is produced by the caller's own proxy, so a retry is re-faulted immediately — the retries happen, cost nothing in upstream load, and change nothing. That is a genuinely useful lesson about what retries are for: they recover from *transient* failures, and an injected fault is not transient.

The third is the most practically valuable. Section 040 module 3 made the point that ejection needs consecutive failures on one endpoint, and that healthy endpoints dilute them. An abort percentage gives you a dial to find out what failure rate your thresholds actually respond to, before an incident does the experiment for you.

> [!TIP]
> **Try it — make a timeout fire on demand**
>
> ```sh
> kubectl -n fault-demo patch virtualservice notification --type merge -p '
> spec:
>   http:
>     - fault:
>         delay:
>           fixedDelay: 7s
>           percentage:
>             value: 100
>       timeout: 3s
>       route:
>         - destination:
>             host: notification-service'
> kubectl -n fault-demo run t4 --rm -i --restart=Never --image=curlimages/curl -- \
>   curl -s -o /dev/null -w '%{http_code} %{time_total}s\n' -X POST http://booking-service/book
> kubectl -n fault-demo logs -l app=booking-service -c istio-proxy --tail=3 | grep -E 'UT|FI'
> ```
>
> Expect something like:
>
> ```text
> 200 3.05s
> [2026-09-27T12:31:02.117Z] "POST /notify HTTP/1.1" 504 UT upstream_response_timeout ...
> ```
>
> Read those two lines together, because they say different things. The **inner** call to `notification-service` timed out at three seconds with `UT` — the deadline fired exactly as designed. The **outer** response to curl is whatever `booking-service` chose to do about that, which here is still a `200`. A timeout firing correctly and the user still getting an answer is the system working; if the outer code had been a `500`, you would have learned that `booking-service` has no fallback.

## Finding a fault somebody left behind

An injected fault is configuration. It survives restarts, redeploys and your going home. An unscoped `abort` left in place is a silent, permanent outage for every caller of that host, and nothing about the cluster looks unhealthy.

Two ways to find one:

- **`istioctl proxy-config routes ... -o json | grep -i fault`** on a caller, which shows whether the proxy currently holds a fault filter.
- **The `FI` response flag** in access logs, which identifies injected failures in bulk across a namespace.

> [!TIP]
> **Try it — the fault filter in the caller's route config**
>
> ```sh
> istioctl proxy-config routes deploy/booking-service-v1 -n fault-demo -o json | grep -i -A10 '"fault"'
> ```
>
> Expect something like:
>
> ```text
> "fault": {
>   "delay": {
>     "fixedDelay": "7s",
>     "percentage": {
>       "numerator": 100,
>       "denominator": "HUNDRED"
> ```
>
> The proxy queried is `booking-service`, the **caller** — confirming once more that a fault for host `notification-service` is enforced on the calling side. Run this against a proxy you did not configure and a hit means somebody's test is still live.

Clean up when you are done:

```sh
kubectl -n fault-demo delete virtualservice notification
```

## Common pitfalls

> [!WARNING]
> **Putting the fault on the wrong host.** It belongs on the `VirtualService` of the service being *called*. Name the host you want to pretend is broken.
>
> **Looking for the injected error in the destination's logs.** An aborted request never arrives there. Look at the caller's log, and check for the `FI` flag.
>
> **The application's own retries hiding the fault.** A 50% abort rate can look like 5% if a client library retries. Check the proxy access log, not just the final response a user sees.
>
> **Leaving a fault in place.** An unscoped `abort` is a silent outage for every caller of that host, and it survives restarts. Scope it with a header match from the start, and delete it afterwards.
>
> **Confusing `delay` with a slow failure.** `delay` still succeeds. If you want an error that is `abort`; the two are independent and compose on one rule.
>
> **Omitting `percentage` and expecting nothing to happen.** The default is 100%.
>
> **Testing a percentage with five requests.** Per-request, independent draws — the same sampling caution as every other percentage in this course.
>
> **Scoping on a header the intermediate service does not forward.** The fault never fires and the configuration looks wrong when the problem is header propagation.
>
> **Reading only the outer response.** In a multi-hop chain the interesting result is often the inner one, in the intermediate service's proxy log.

> *A fault is configuration, not a session — it outlives your terminal, so scope it with a match and delete it when you are finished.*

## Reference

- [Fault injection task](https://istio.io/latest/docs/tasks/traffic-management/fault-injection/) — including the header-scoped example.
- [HTTPFaultInjection API](https://istio.io/latest/docs/reference/config/networking/virtual-service/#HTTPFaultInjection) — the full schema.
- [Envoy fault filter](https://www.envoyproxy.io/docs/envoy/latest/configuration/http/http_filters/fault_filter) — what the filter does and in what order.
- [Traffic management concepts](https://istio.io/latest/docs/concepts/traffic-management/) — where fault injection sits relative to routing and resilience.
