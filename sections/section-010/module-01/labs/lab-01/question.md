# Question

Solve this question on: `terminal`

Namespace `routing-demo` runs two versions of one application behind a single Service:

* `notification-service-v1` — pods labelled `version: v1`, answers `["EMAIL"]`
* `notification-service-v2` — pods labelled `version: v2`, answers `["EMAIL","SMS"]`
* `notification-service` — one Service on port 80 selecting on `app` only, so both versions receive traffic
* `tester` — a client pod with `curl`

Istio is installed and every pod in `routing-demo` is injected. There is no [`VirtualService`](https://istio.io/latest/docs/reference/config/networking/virtual-service/) and no [`DestinationRule`](https://istio.io/latest/docs/reference/config/networking/destination-rule/).

Configure routing for host `notification-service` in namespace `routing-demo` so that:

1.  A `DestinationRule` named `notification-service` defines exactly two subsets, **`v1`** and **`v2`**, each selecting on the pods' **`version`** label.
2.  A `VirtualService` named `notification-service` routes requests carrying the header **`testing: true`** to subset **`v2`**.
3.  The same `VirtualService` routes requests whose URI starts with **`/notify/beta`** to subset **`v2`**.
4.  The same `VirtualService` routes requests carrying the query parameter **`version=2`** to subset **`v2`**.
5.  **Every other request** goes to subset **`v1`**. A request with no header, no matching path and no query parameter must reach `v1` every time — not sometimes.
6.  The three specific rules must each be reachable. A default route that swallows traffic before them is a failure, even though it produces no error.
7.  Leave the Deployments and the Service unchanged. Do not add a third Deployment, and do not change the Service selector.

The grader sends live traffic from the `tester` pod and reads the responses, so the rules have to work — not merely exist.

---

---

## Reference

The official documentation for everything this task touches — open these rather than trying to recall field names:

- [VirtualService API](https://istio.io/latest/docs/reference/config/networking/virtual-service/) — the whole object: `hosts`, `gateways`, and every field an `http` rule can carry
- [DestinationRule API](https://istio.io/latest/docs/reference/config/networking/destination-rule/) — `host`, `subsets`, and the `trafficPolicy` block
- [Subsets and traffic policy](https://istio.io/latest/docs/reference/config/networking/destination-rule/#Subset) — how a subset name maps to pod labels
- [HTTPMatchRequest API](https://istio.io/latest/docs/reference/config/networking/virtual-service/#HTTPMatchRequest) — every match key: `headers`, `uri`, `queryParams`, `method`, `withoutHeaders`
- [StringMatch API](https://istio.io/latest/docs/reference/config/networking/virtual-service/#StringMatch) — the `exact` / `prefix` / `regex` choice and what each means
- [Debugging Envoy and istiod](https://istio.io/latest/docs/ops/diagnostic-tools/proxy-cmd/) — `proxy-status`, `proxy-config` and `x describe` in full
- [Istio analyzer messages](https://istio.io/latest/docs/reference/config/analysis/) — every `IST####` code and what triggers it
