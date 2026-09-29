# Question

Solve this question on: `terminal`

Namespace `orders` holds a two-hop call chain shared with other people:

```text
your curl pod  →  booking-service  →  notification-service
```

* `booking-service` — a Service on port 80. Calls `notification-service` on every `POST /book`, forwarding request headers.
* `notification-service` — a Service on port 80, the dependency.
* No permanent client pod. Use `kubectl -n orders run t --rm -i --restart=Never --image=curlimages/curl -- ...`

Istio is installed, both workloads are injected, and there is no [`VirtualService`](https://istio.io/latest/docs/reference/config/networking/virtual-service/).

You are running two chaos experiments against the dependency. Both must be invisible to everybody else.

Create a `VirtualService` named `notification` for host **`notification-service`** with exactly **three** `http` rules, in this order:

**Rule 1 — does a retry policy survive a hard failure?**

1.  Matches the header **`x-chaos: abort`**.
2.  Injects an `abort` with `httpStatus` **`503`** at **100%**.
3.  Carries a retry policy on the **same rule**: `attempts` **2**, `perTryTimeout` **`1s`**, `retryOn` **`gateway-error`**. It is correct configuration, and you will watch it do nothing.
4.  Sets `timeout` to **`5s`** — comfortably above the retry budget, so the retries are not truncated.
5.  Routes to `notification-service`.

**Rule 2 — does a timeout fire when a dependency goes slow?**

6.  Matches the header **`x-chaos: delay`**.
7.  Injects a `delay` with `fixedDelay` **`7s`** at **100%**.
8.  Routes to `notification-service`, with **no** timeout and **no** retries on this rule.

**Rule 3 — everyone else**

9.  No `match` block, no fault, no timeout, no retries. Routes to `notification-service`.

Then create a second `VirtualService` named **`booking`** for host
**`booking-service`**: one rule, no `match`, `timeout` **`2s`**, routing to
`booking-service`.

10. The timeout for the delay experiment goes **there**, one hop above the fault, and not beside it. An injected delay is produced by the fault filter, which runs before the router in the same proxy, so a `timeout` on the same rule never sees it and the request waits out all seven seconds. Only a timeout enforced by a different proxy — the client's, on its call to `booking-service` — can cut a fabricated delay short.

**What the grader checks**

11. A request with `x-chaos: abort` fails, and `booking-service`'s proxy log shows exactly **1** attempt against `notification-service`, carrying the **`FI`** flag — *not* three. The retry policy is configured and still never runs: an injected abort is a local reply from the fault filter, which sits before the router in the filter chain, so the router never sees a failed upstream attempt to retry. Retries rescue *transient upstream* failures; a fabricated one is neither.
12. A request with `x-chaos: delay` fails in roughly **2 seconds**, and the **client** proxy's log carries the **`UT`** flag for `booking-service`.
13. Five requests with **no** `x-chaos` header return **200**, quickly.
14. The `VirtualService` is for host `notification-service`, and the faults are visible in `booking-service`'s route configuration.

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
- [HTTPFaultInjection API](https://istio.io/latest/docs/reference/config/networking/virtual-service/#HTTPFaultInjection) — `delay`, `abort` and the percentage fields
- [Istio analyzer messages](https://istio.io/latest/docs/reference/config/analysis/) — every `IST####` code and what triggers it
