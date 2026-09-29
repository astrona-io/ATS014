# Question

Solve this question on: `terminal`

Namespace `fault-demo` holds a two-hop call chain:

```text
your curl pod  →  booking-service  →  notification-service
```

* `booking-service` — a Service on port 80. Calls `notification-service` on every `POST /book`, and forwards request headers to it.
* `notification-service` — a Service on port 80, the dependency.
* There is **no permanent client pod**. Create throwaway ones with
  `kubectl -n fault-demo run t --rm -i --restart=Never --image=curlimages/curl -- ...`

Istio is installed, both workloads are injected, and there is no [`VirtualService`](https://istio.io/latest/docs/reference/config/networking/virtual-service/).

Other people are using this namespace, so your test must not break their traffic.

Create **two** `VirtualService` objects.

**A `VirtualService` named `notification` for host `notification-service`**, with exactly **two** `http` rules, in this order:

**Rule 1 — the scoped fault**

1.  Matches the header **`end-user: tester`**.
2.  Injects **both**:
    *   a `delay` with `fixedDelay` **`7s`** at **100%**
    *   an `abort` with `httpStatus` **`500`** at **100%**
3.  Routes to `notification-service`.

**Rule 2 — everyone else**

4.  No `match` block. Routes to `notification-service` with no fault and no timeout.

**A `VirtualService` named `booking` for host `booking-service`**

5.  One rule, no `match`, `timeout` **`3s`**, routing to `booking-service`.

Why the timeout lives there and not next to the fault: an injected delay is
produced by the fault filter, which runs **before** the router in the same
proxy, so a `timeout` on that same rule never sees it — the request waits the
full 7 seconds. A timeout only cuts an injected delay when it is enforced by a
**different** proxy, one hop upstream. Here the delay is enforced in
`booking-service`'s sidecar (on its call to `notification-service`), and the
3-second timeout is enforced in the **client's** sidecar (on its call to
`booking-service`).

**What the grader checks**

6.  A `POST /book` carrying `end-user: tester` does **not** return 200, and comes back in roughly **3 seconds** — the 7-second delay runs into the 3-second timeout one hop up, so the timeout fires before the abort ever would.
7.  A `POST /book` with **no** header returns **200** in well under a second, five times in a row. Unscoped faults fail this check.
8.  The **client** proxy's access log contains a `504 UT` line for `booking-service` — the injected delay really made the route timeout fire.
9.  The fault appears in `booking-service`'s route configuration, confirming it is enforced in the **caller's** proxy.
10. The fault is on the `VirtualService` for **`notification-service`**, not for `booking-service`; the `booking-service` object carries the timeout and no fault.

---

---

## Reference

The official documentation for everything this task touches — open these rather than trying to recall field names:

- [VirtualService API](https://istio.io/latest/docs/reference/config/networking/virtual-service/) — the whole object: `hosts`, `gateways`, and every field an `http` rule can carry
- [Istio Kubernetes Gateway API task](https://istio.io/latest/docs/tasks/traffic-management/ingress/gateway-api/) — `GatewayClass`, `Gateway`, `HTTPRoute`, `parentRefs` and `allowedRoutes`
- [HTTPMatchRequest API](https://istio.io/latest/docs/reference/config/networking/virtual-service/#HTTPMatchRequest) — every match key: `headers`, `uri`, `queryParams`, `method`, `withoutHeaders`
- [StringMatch API](https://istio.io/latest/docs/reference/config/networking/virtual-service/#StringMatch) — the `exact` / `prefix` / `regex` choice and what each means
- [HTTPRoute API](https://istio.io/latest/docs/reference/config/networking/virtual-service/#HTTPRoute) — `timeout` alongside `retries`, `fault` and `mirror` on one rule
- [HTTPFaultInjection API](https://istio.io/latest/docs/reference/config/networking/virtual-service/#HTTPFaultInjection) — `delay`, `abort` and the percentage fields
- [Debugging Envoy and istiod](https://istio.io/latest/docs/ops/diagnostic-tools/proxy-cmd/) — `proxy-status`, `proxy-config` and `x describe` in full
- [Istio analyzer messages](https://istio.io/latest/docs/reference/config/analysis/) — every `IST####` code and what triggers it
