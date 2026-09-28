# `fault.abort`

> Prerequisite: [`fault.delay`](./course-01-fault-delay.md). Next: [Scoping, Composition And Hazards](./course-03-scoping-composition-and-hazards.md).

The other half, and it is not "delay with an error at the end". This part covers what makes an abort structurally different, where the evidence lives, and how to inject into only some traffic.

## Immediate, and never forwarded

```yaml
fault:
  abort:
    httpStatus: 500
    percentage:
      value: 50
```

The proxy returns the status **immediately**, without contacting the upstream at all.

```text
   delay:                          abort:
   caller ──► [hold 2s] ──► upstream    caller ──► [return 500] ✗ upstream never contacted
          ◄──────────────── response            ◄──────────────
```

The consequence to internalise: **the upstream has no record of an aborted request.** Its access log is empty for it, its metrics are unmoved, its application never ran. If you go looking for the injected error on the destination you will not find it, and concluding "the fault is not working" is the natural mistake.

The evidence lives in the **caller's** access log, because the caller's proxy is what produced the response.

`abort` also accepts `grpcStatus` for gRPC traffic, and `httpStatus` is what HTTP tasks use.

## Sampling with `percentage`

`percentage.value` is a float and is the share of **matching** requests affected. Leave the block out and 100% of matched traffic gets the fault — the default is 100, not 0, which is a reasonable thing to get wrong under exam pressure.

As with every percentage in this course the decision is per request and independent, so measure over enough requests to see a rate rather than a coincidence.

> [!TIP]
> **Try it — half the calls fail, none of them reach the upstream**
>
> ```sh
> kubectl -n fault-demo patch virtualservice notification --type merge -p '
> spec:
>   http:
>     - fault:
>         abort:
>           httpStatus: 500
>           percentage:
>             value: 50
>       route:
>         - destination:
>             host: notification-service'
> kubectl -n fault-demo run t2 --rm -i --restart=Never --image=curlimages/curl -- sh -c \
>   'for i in $(seq 1 20); do curl -s -o /dev/null -w "%{http_code} " -X POST http://booking-service/book; done; echo'
> ```
>
> Expect something like:
>
> ```text
> 200 500 200 200 500 500 200 500 200 200 500 200 500 500 200 200 500 200 200 500
> ```
>
> Roughly half, and immediately — no two-second pause anywhere, unlike Part 1. The `500` the caller sees was manufactured by `booking-service`'s own sidecar.

## Proving the upstream was never involved

The asymmetry between the two logs is the cleanest demonstration of what `abort` does, and it is the same shape as the circuit-breaker evidence in section 040 module 2.

> [!TIP]
> **Try it — the caller logged it, the destination did not**
>
> ```sh
> kubectl -n fault-demo logs -l app=booking-service -c istio-proxy --tail=40 | grep -c ' 500 '
> kubectl -n fault-demo logs -l app=notification-service -c istio-proxy --tail=40 | grep -c ' 500 '
> kubectl -n fault-demo logs -l app=booking-service -c istio-proxy --tail=40 | grep ' 500 ' | head -1
> ```
>
> Expect something like:
>
> ```text
> 9
> 0
> [2026-09-27T12:18:44.902Z] "POST /notify HTTP/1.1" 500 FI fault_filter_abort - "-" 0 18 0 - ...
> ```
>
> Nine on the caller's side, zero on the destination's. And note the response flag: **`FI`** — fault injected — with `fault_filter_abort` naming the cause. That flag is how you tell an injected 500 from a real one, and it belongs in the same mental table as `UT`, `UO` and `UH` from section 040.

That gives the module its diagnostic rule: **a 5xx with `FI` in the caller's log is yours.** Anything else is the application's.

## Delay and abort together

Both halves can appear on the same rule, and they are independent:

```yaml
fault:
  delay:
    fixedDelay: 1s
    percentage:
      value: 100
  abort:
    httpStatus: 503
    percentage:
      value: 30
```

Read that as: every matching request is held for a second, and 30% of them are then aborted. The delay applies first, so an aborted request is *also* slow — which models a dependency that times out rather than one that fails fast, and is a more realistic shape for most real outages.

The two percentages are independent draws. They do not need to sum to anything.

> *`abort` is produced by the caller's proxy and carries the `FI` response flag — the upstream never hears about it.*

## Reference

- [Fault injection task](https://istio.io/latest/docs/tasks/traffic-management/fault-injection/) — the abort walkthrough.
- [HTTPFaultInjection.Abort](https://istio.io/latest/docs/reference/config/networking/virtual-service/#HTTPFaultInjection-Abort) — `httpStatus`, `grpcStatus` and `percentage`.
- [Envoy response flags](https://www.envoyproxy.io/docs/envoy/latest/configuration/observability/access_log/usage#config-access-log-format-response-flags) — `FI` alongside `UT`, `UO` and `UH`.
- [Envoy fault filter](https://www.envoyproxy.io/docs/envoy/latest/configuration/http/http_filters/fault_filter) — the filter Istio configures, including the ordering of delay and abort.
