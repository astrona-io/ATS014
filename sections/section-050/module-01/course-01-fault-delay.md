# Part 1 — `fault.delay`

> Prerequisite: [the module landing page](./course.md). Next: [Part 2 — `fault.abort`](./course-02-fault-abort.md).

The first half of the feature, and the one that models the failure mode people most often forget to test: a dependency that is not broken, just slow.

## The baseline

> [!TIP]
> **Try it — the call chain working normally**
>
> ```sh
> kubectl -n fault-demo run t0 --rm -i --restart=Never --image=curlimages/curl -- \
>   curl -s -o /dev/null -w '%{http_code} %{time_total}s\n' -X POST http://booking-service/book
> ```
>
> Expect something like:
>
> ```text
> 200 0.043s
> ```
>
> Forty milliseconds for a request crossing two services. Both numbers are the baseline — the status code and the latency are what the two halves of this module each change, one at a time.

## The field

`fault` sits on the HTTP rule, alongside `route` and `timeout`. Its `delay` half holds the request for `fixedDelay` and then forwards it normally:

```yaml
http:
  - fault:
      delay:
        fixedDelay: 2s
        percentage:
          value: 100
    route:
      - destination:
          host: notification-service
```

**The request still succeeds.** The caller gets a correct response, two seconds late. That is precisely what you want for testing a timeout, because it separates "slow" from "broken" — and a real degraded dependency usually looks like this, not like a clean error.

There is also `exponentialDelay` in the API, intended for modelling growing latency. `fixedDelay` is what tasks and examples use; recognise the other rather than reaching for it.

## Which `VirtualService` owns the fault

This is the detail worth being precise about, because getting it wrong produces a working experiment that tests the wrong thing.

The fault is **enforced by the caller's proxy**, but the object is keyed by the **callee's hostname**. So a `VirtualService` for host `notification-service` injects faults into calls *to* `notification-service`, and the code that runs is inside `booking-service`'s sidecar:

```text
   curl ──► booking-service ────────────► notification-service
             │                  ▲
             │                  │
             └─ its sidecar enforces the fault here,
                using the VirtualService whose host is
                notification-service
```

Put the fault on `booking-service` instead and you delay the inbound request from curl — a different experiment, testing curl's patience rather than `booking-service`'s timeout handling.

The rule of thumb: **name the host you want to pretend is broken.**

> [!TIP]
> **Try it — two seconds added to the second hop**
>
> ```sh
> kubectl apply -f - <<'EOF'
> apiVersion: networking.istio.io/v1
> kind: VirtualService
> metadata:
>   name: notification
>   namespace: fault-demo
> spec:
>   hosts:
>     - notification-service
>   http:
>     - fault:
>         delay:
>           fixedDelay: 2s
>           percentage:
>             value: 100
>       route:
>         - destination:
>             host: notification-service
> EOF
> kubectl -n fault-demo run t1 --rm -i --restart=Never --image=curlimages/curl -- \
>   curl -s -o /dev/null -w '%{http_code} %{time_total}s\n' -X POST http://booking-service/book
> ```
>
> Expect something like:
>
> ```text
> 200 2.061s
> ```
>
> Still a `200`, now two seconds slower. Nothing was deployed, restarted or patched in either application — `booking-service` is simply experiencing a slow dependency, which is the condition its timeout configuration is supposed to handle.

## The delay is real work being held

Two clarifications that prevent misreading the mechanism.

**The upstream never sees the delay.** The proxy holds the request before forwarding it, so `notification-service` receives it two seconds late and responds normally. Its own latency metrics are untouched — which is what makes this a clean test of the *caller*.

**The delay consumes caller resources.** For those two seconds, `booking-service` has a request in flight: a connection, a worker, a slot in any pool. That is not an artefact of the test; it is exactly what a real slow dependency does, and it is why a delay of a few seconds against a tight connection pool (section 040, module 2) will produce overflow rejections as a *side effect*. Worth knowing so you do not misread those 503s.

> *`fault.delay` produces a slow success, enforced in the caller's proxy, on the `VirtualService` of the host you want to pretend is struggling.*

## Reference

- [Fault injection task](https://istio.io/latest/docs/tasks/traffic-management/fault-injection/) — the upstream walkthrough for both halves.
- [HTTPFaultInjection API](https://istio.io/latest/docs/reference/config/networking/virtual-service/#HTTPFaultInjection) — `delay`, `abort`, and the percentage fields.
- [HTTPFaultInjection.Delay](https://istio.io/latest/docs/reference/config/networking/virtual-service/#HTTPFaultInjection-Delay) — `fixedDelay` and `exponentialDelay`.
- [Request timeouts task](https://istio.io/latest/docs/tasks/traffic-management/request-timeouts/) — the section 040 field this is built to exercise.
