# Question

Solve this question on: `terminal`

Namespace `payments` runs a ledger service with one poisoned replica, and a load generator:

* `ledger-good` — **2 replicas**, healthy. `/delay/<seconds>` sleeps; `/status/<code>` returns that status.
* `ledger-bad` — **1 replica** of nginx returning **503 to every request** while passing its readiness probe.
* `ledger` — one Service on port 8000 in front of **all three** pods
* `fortio` — a load generator. Its pod has containers `fortio` and `istio-proxy`.

Istio is installed, every pod is injected, and there is no [`VirtualService`](https://istio.io/latest/docs/reference/config/networking/virtual-service/) and no [`DestinationRule`](https://istio.io/latest/docs/reference/config/networking/destination-rule/). Roughly a third of all traffic currently fails.

Deliver a resilient path to this service.

**VirtualService `ledger`, for host `ledger`, with exactly two `http` rules in this order**

1.  **First**, a rule matching method **`POST`**: routes to `ledger` port 8000, `timeout` **`3s`**, and retries **explicitly disabled**. A retried payment is a duplicate payment, and omitting the `retries` block is not the same as disabling it.
2.  **Second**, the catch-all read rule: routes to `ledger` port 8000, `retries` with `attempts` **2**, `perTryTimeout` **`1s`**, `retryOn` **`gateway-error`**, and a `timeout` that is large enough for the whole retry budget to run. Work the budget out rather than guessing.

**DestinationRule `ledger`, for host `ledger`**

3.  `connectionPool` with `tcp.maxConnections` **2** and `http.http1MaxPendingRequests` **2**.
4.  `outlierDetection` with `consecutive5xxErrors` **3**, `interval` **`5s`**, `baseEjectionTime` **`30s`**, and a `maxEjectionPercent` that can actually eject one endpoint out of three.
5.  `loadBalancer.localityLbSetting` with `enabled: true`.

**What the grader checks**

6.  A `GET /status/503` produces **3** requests at the service — the original plus two retries.
7.  A `POST /status/503` produces exactly **1**.
8.  The read rule's `timeout` is at least `(attempts + 1) × perTryTimeout`.
9.  A concurrent `fortio` run produces `503`s carrying the **`UO`** flag, and `upstream_rq_pending_overflow` increases.
10. After driving traffic, the failing endpoint is ejected — `OUTLIER CHECK: FAILED`, or the ejection counters have moved.
11. All three ledger pods are still running with their original replica counts, and the Service selector is unchanged.

---

---

## Reference

The official documentation for everything this task touches — open these rather than trying to recall field names:

- [VirtualService API](https://istio.io/latest/docs/reference/config/networking/virtual-service/) — the whole object: `hosts`, `gateways`, and every field an `http` rule can carry
- [DestinationRule API](https://istio.io/latest/docs/reference/config/networking/destination-rule/) — `host`, `subsets`, and the `trafficPolicy` block
- [Istio Kubernetes Gateway API task](https://istio.io/latest/docs/tasks/traffic-management/ingress/gateway-api/) — `GatewayClass`, `Gateway`, `HTTPRoute`, `parentRefs` and `allowedRoutes`
- [Subsets and traffic policy](https://istio.io/latest/docs/reference/config/networking/destination-rule/#Subset) — how a subset name maps to pod labels
- [HTTPMatchRequest API](https://istio.io/latest/docs/reference/config/networking/virtual-service/#HTTPMatchRequest) — every match key: `headers`, `uri`, `queryParams`, `method`, `withoutHeaders`
- [StringMatch API](https://istio.io/latest/docs/reference/config/networking/virtual-service/#StringMatch) — the `exact` / `prefix` / `regex` choice and what each means
- [HTTPRoute API](https://istio.io/latest/docs/reference/config/networking/virtual-service/#HTTPRoute) — `timeout` alongside `retries`, `fault` and `mirror` on one rule
- [HTTPRetry API](https://istio.io/latest/docs/reference/config/networking/virtual-service/#HTTPRetry) — `attempts`, `perTryTimeout`, `retryOn` and `retriableStatusCodes`
- [TCPRoute and TLSRoute APIs](https://istio.io/latest/docs/reference/config/networking/virtual-service/#TCPRoute) — what a connection-level match can see when there is no request to read
- [ConnectionPoolSettings API](https://istio.io/latest/docs/reference/config/networking/destination-rule/#ConnectionPoolSettings) — `tcp.maxConnections`, `http1MaxPendingRequests`, `http2MaxRequests`
- [OutlierDetection API](https://istio.io/latest/docs/reference/config/networking/destination-rule/#OutlierDetection) — `consecutive5xxErrors`, `interval`, `baseEjectionTime`, `maxEjectionPercent`
- [ConsistentHashLB API](https://istio.io/latest/docs/reference/config/networking/destination-rule/#LoadBalancerSettings-ConsistentHashLB) — the four hash sources, `ttl`, and `minimumRingSize`
- [LoadBalancerSettings API](https://istio.io/latest/docs/reference/config/networking/destination-rule/#LoadBalancerSettings) — the `simple` enum and the `consistentHash` alternative
- [LocalityLoadBalancerSetting API](https://istio.io/latest/docs/reference/config/networking/destination-rule/#LocalityLoadBalancerSetting) — `distribute`, `failover` and the health dependency
- [Debugging Envoy and istiod](https://istio.io/latest/docs/ops/diagnostic-tools/proxy-cmd/) — `proxy-status`, `proxy-config` and `x describe` in full
- [Istio analyzer messages](https://istio.io/latest/docs/reference/config/analysis/) — every `IST####` code and what triggers it
