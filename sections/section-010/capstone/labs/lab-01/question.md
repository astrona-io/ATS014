# Question

Solve this question on: `terminal`

You have a mesh with three injected namespaces and no Istio traffic configuration at all. It runs with `outboundTrafficPolicy: REGISTRY_ONLY`, so a destination the proxy no longer carries is genuinely unreachable rather than quietly passed through.

**`storefront`**
* `catalog-v1` — pods labelled `version: v1`, answers `["EMAIL"]` to `POST /notify`
* `catalog-v2` — pods labelled `version: v2`, answers `["EMAIL","SMS"]`
* `catalog` — one Service on port **8000** selecting on `app` only, so both versions receive traffic
* `shopper` — a client pod with `curl`

**`partners`**
* `pricing` — a Service on port 8000 that `storefront` legitimately calls

**`archive`**
* `coldstore` — a Service on port 8000 that nothing in `storefront` should be able to reach

Deliver the following specification. Both halves are graded with live traffic and with the proxy's own configuration dump.

**Routing**

1.  A [`DestinationRule`](https://istio.io/latest/docs/reference/config/networking/destination-rule/) named `catalog` in `storefront` defining exactly two subsets, **`v1`** and **`v2`**, each selecting on the pods' **`version`** label.
2.  A [`VirtualService`](https://istio.io/latest/docs/reference/config/networking/virtual-service/) named `catalog` in `storefront` for host `catalog`, sending to subset **`v2`**:
    *   requests carrying the header **`x-channel: mobile`**
    *   requests whose URI starts with **`/notify/preview`**
    *   requests carrying the query parameter **`beta=1`**
3.  Every other request must reach subset **`v1`** — every time, not sometimes.
4.  All three specific rules must be reachable. A default route placed above them produces no error and is still a failure.
5.  A request carrying `x-channel: web` must reach `v1`. The header rule matches the value `mobile`, not merely the presence of the header.

**Scoping**

6.  A [`Sidecar`](https://istio.io/latest/docs/reference/config/networking/sidecar/) named **`default`** in `storefront`, applying to **every workload in that namespace** — no `workloadSelector`.
7.  Its `egress` hosts must be exactly three things: the proxy's **own namespace**, **`istio-system`**, and **`partners`**.
8.  `http://pricing.partners:8000/get` must still return **200** from `shopper`.
9.  `archive` must be absent from the `shopper` proxy's cluster list, and `http://coldstore.archive:8000/get` must **not** return 200.
10. The routing from the first half must still work with the `Sidecar` in place — scope the proxy's own namespace in, or you will break the thing you just built.

**Leave alone**

11. Do not change the `catalog` Service selector, do not add or remove Deployments, and do not delete or scale down `coldstore` — the traffic to `archive` must be stopped by scoping, not by removing the target.

---

---

## Reference

The official documentation for everything this task touches — open these rather than trying to recall field names:

- [VirtualService API](https://istio.io/latest/docs/reference/config/networking/virtual-service/) — the whole object: `hosts`, `gateways`, and every field an `http` rule can carry
- [DestinationRule API](https://istio.io/latest/docs/reference/config/networking/destination-rule/) — `host`, `subsets`, and the `trafficPolicy` block
- [Sidecar API](https://istio.io/latest/docs/reference/config/networking/sidecar/) — `workloadSelector`, `egress.hosts` and the `<namespace>/<host>` syntax
- [Subsets and traffic policy](https://istio.io/latest/docs/reference/config/networking/destination-rule/#Subset) — how a subset name maps to pod labels
- [HTTPMatchRequest API](https://istio.io/latest/docs/reference/config/networking/virtual-service/#HTTPMatchRequest) — every match key: `headers`, `uri`, `queryParams`, `method`, `withoutHeaders`
- [StringMatch API](https://istio.io/latest/docs/reference/config/networking/virtual-service/#StringMatch) — the `exact` / `prefix` / `regex` choice and what each means
- [MeshConfig outboundTrafficPolicy](https://istio.io/latest/docs/reference/config/istio.mesh.v1alpha1/#MeshConfig-OutboundTrafficPolicy) — `ALLOW_ANY` versus `REGISTRY_ONLY`
- [Sidecar injection](https://istio.io/latest/docs/setup/additional-setup/sidecar-injection/) — the namespace label, the pod annotation, and when injection happens
- [Debugging Envoy and istiod](https://istio.io/latest/docs/ops/diagnostic-tools/proxy-cmd/) — `proxy-status`, `proxy-config` and `x describe` in full
- [Istio analyzer messages](https://istio.io/latest/docs/reference/config/analysis/) — every `IST####` code and what triggers it
