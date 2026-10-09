# Summary

Kubernetes decides which pods belong to a Service by their labels and their readiness. It never looks at the responses a pod gives to real requests, so a pod can be `Running`, pass its readiness probe and still fail every request. A readiness probe is an active check: the kubelet asks the pod about itself. Outlier detection is a passive check: each client's sidecar proxy watches the responses it already receives, and stops sending requests to an endpoint that keeps failing. Because it is passive, some requests must fail before it can act.

You configure outlier detection in a `DestinationRule`, under `trafficPolicy.outlierDetection`. `consecutive5xxErrors` counts 5xx responses in a row from one endpoint, and one success from that endpoint resets the count. So it catches an endpoint that fails every request quickly, and may never catch one that fails only some of them. `consecutive5xxErrors` is 5 as soon as an `outlierDetection` block exists. To count only `502`, `503` and `504` with `consecutiveGatewayErrors`, you must also set `consecutive5xxErrors: 0`.

An ejection removes the endpoint from one proxy's load-balancing pool, and it always ends. It happens as soon as the count reaches the limit. It lasts `baseEjectionTime` multiplied by the number of times the endpoint has been ejected, and the endpoint comes back at the next `interval` check after that. A pod that stays broken therefore produces a cycle of short error bursts with growing gaps, not a stable state.

Two fields protect the pool from losing too many endpoints. `maxEjectionPercent` defaults to 10%, which blocks every ejection on a Service with two or three endpoints, and the `ejections_overflow` counter shows each blocked attempt. `minHealthPercent` switches outlier detection off when the healthy share of the pool drops below it; its default is `0%`.

Each proxy decides on its own, from its own responses. Kubernetes never changes: the EndpointSlice still lists the ejected pod, and only the `OUTLIER CHECK` column of `istioctl proxy-config endpoints` and the proxy's counters show the ejection. A connection pool and outlier detection together in one `DestinationRule` form a circuit breaker: the pool refuses extra requests with `503 UO`, and outlier detection removes endpoints that keep failing.

Key facts to remember:

- `consecutive5xxErrors` defaults to 5 inside an `outlierDetection` block; `consecutiveGatewayErrors` defaults to off.
- `interval` defaults to `10s`; ejection time is `baseEjectionTime` × the ejection count, capped by Envoy at 300 seconds or `baseEjectionTime` if that is larger.
- `maxEjectionPercent` defaults to 10%; raise it to at least 50 on a two-endpoint Service and at least 34 on a three-endpoint Service.
- `ejections_active`, `ejections_total` and `ejections_enforced_consecutive_5xx` prove an ejection; they need the `sidecar.istio.io/statsInclusionPrefixes` annotation.
- Keep the connection pool and outlier detection for one host in one `DestinationRule`.

<!-- astrona:playground:destroy -->
