# Question

Solve this question on: `terminal`

Namespace `shifting-demo` runs two versions of one application behind a single Service:

* `notification-service-v1` — pods labelled `version: v1`, answers `["EMAIL"]`, **1 replica**
* `notification-service-v2` — pods labelled `version: v2`, answers `["EMAIL","SMS"]`, **1 replica**
* `notification-service` — one Service on port 80 selecting on `app` only
* `tester` — a client pod with `curl`

Istio is installed, every pod is injected, and there is no [`VirtualService`](https://istio.io/latest/docs/reference/config/networking/virtual-service/) and no [`DestinationRule`](https://istio.io/latest/docs/reference/config/networking/destination-rule/).

You are running a canary for `v2`. Deliver the following:

1.  A `DestinationRule` named `notification-service` defining exactly two subsets, **`v1`** and **`v2`**, each selecting on the pods' **`version`** label.
2.  A `VirtualService` named `notification` for host `notification-service`, holding **two** `http` rules in this order:
    *   **First**, a rule matching the header **`x-internal: true`** that sends those requests to subset **`v2`** — internal testers always get the new version, whatever the canary percentage is.
    *   **Second**, a weighted rule splitting everything else **70% to `v1`** and **30% to `v2`**.
3.  The weighted rule must be a single route block with two destinations carrying `weight: 70` and `weight: 30`.
4.  A request carrying `x-internal: true` must reach `v2` every time — it must not be part of the split.
5.  Ordinary traffic must reach **both** versions, in roughly the configured proportion. The grader sends 200 requests and checks the share is in a sensible band, so an all-v1 or all-v2 result fails.
6.  Do **not** change either Deployment's replica count. Traffic share is a weight, not a pod count, and the grader checks both Deployments still run exactly 1 replica.
7.  Do not change the Service selector, and do not add a third Deployment.

---

---

## Reference

The official documentation for everything this task touches — open these rather than trying to recall field names:

- [VirtualService API](https://istio.io/latest/docs/reference/config/networking/virtual-service/) — the whole object: `hosts`, `gateways`, and every field an `http` rule can carry
- [DestinationRule API](https://istio.io/latest/docs/reference/config/networking/destination-rule/) — `host`, `subsets`, and the `trafficPolicy` block
- [Subsets and traffic policy](https://istio.io/latest/docs/reference/config/networking/destination-rule/#Subset) — how a subset name maps to pod labels
- [HTTPMatchRequest API](https://istio.io/latest/docs/reference/config/networking/virtual-service/#HTTPMatchRequest) — every match key: `headers`, `uri`, `queryParams`, `method`, `withoutHeaders`
- [StringMatch API](https://istio.io/latest/docs/reference/config/networking/virtual-service/#StringMatch) — the `exact` / `prefix` / `regex` choice and what each means
- [HTTPRouteDestination API](https://istio.io/latest/docs/reference/config/networking/virtual-service/#HTTPRouteDestination) — `destination` plus `weight`, and the rule that weights sum to 100
- [Debugging Envoy and istiod](https://istio.io/latest/docs/ops/diagnostic-tools/proxy-cmd/) — `proxy-status`, `proxy-config` and `x describe` in full
- [Istio analyzer messages](https://istio.io/latest/docs/reference/config/analysis/) — every `IST####` code and what triggers it
