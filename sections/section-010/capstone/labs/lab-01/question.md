# Question

Solve this question on: `terminal`

Route requests to two versions of one service, and limit what the proxies of its namespace can reach. The mesh has three namespaces with sidecar injection switched on, and no Istio traffic configuration at all. Istio 1.30.5 is installed with `outboundTrafficPolicy: REGISTRY_ONLY`. With this setting, a sidecar proxy blocks requests to any host it holds no configuration for, instead of letting them through.

**`storefront`**
* `catalog-v1`: pods labelled `version: v1`; answers `["EMAIL"]` to `POST /notify`
* `catalog-v2`: pods labelled `version: v2`; answers `["EMAIL","SMS"]`
* `catalog`: one Service on port **8000** that selects on the `app` label only, so both versions receive traffic
* `shopper`: a client pod with `curl`

**`partners`**
* `pricing`: a Service on port 8000 that `storefront` needs to call

**`archive`**
* `coldstore`: a Service on port 8000 that nothing in `storefront` may reach

Deliver the following specification. The grader checks both halves with live requests and with the configuration that the `shopper` proxy holds.

**Routing**

1.  A `DestinationRule` named `catalog` in `storefront` that defines exactly two subsets, **`v1`** and **`v2`**, each selecting on the pods' **`version`** label. A subset is a named group of pods.
2.  A `VirtualService` named `catalog` in `storefront` for the host `catalog`, which sends these requests to subset **`v2`**:
    *   requests with the header **`x-channel: mobile`**
    *   requests whose URI path starts with **`/notify/preview`**
    *   requests with the query parameter **`beta=1`**
3.  Every other request must reach subset **`v1`**, every time, not only sometimes.
4.  All three specific rules must be reachable. A default route placed above them gives no error, but it still fails the task.
5.  A request with the header `x-channel: web` must reach `v1`. The header rule matches the value `mobile`, not only the presence of the header.

**Scoping**

6.  A `Sidecar` named **`default`** in `storefront` that applies to **every workload in that namespace**, so it has no `workloadSelector`. It is the only `Sidecar` in `storefront`.
7.  Its `egress` hosts must be exactly three entries: the proxy's **own namespace**, **`istio-system`**, and **`partners`**.
8.  A request from `shopper` to `http://pricing.partners:8000/get` must still return **200**.
9.  `archive` must be absent from the `shopper` proxy's cluster list, and a request to `http://coldstore.archive:8000/get` must **not** return 200.
10. The routing from the first half must still work with the `Sidecar` in place. If the proxy's own namespace is not in the egress hosts, the proxy loses the `catalog` clusters and the routing breaks.

**Leave alone**

11. Do not change the `catalog` Service selector, do not add or remove Deployments, and do not delete or scale down `coldstore`. The `Sidecar` must stop the traffic to `archive`, not the removal of the target.
