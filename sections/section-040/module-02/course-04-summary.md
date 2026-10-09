# Summary

A circuit breaker in Istio is a set of connection pool limits in a `DestinationRule`, under `trafficPolicy.connectionPool`. The sidecar proxy (Envoy) uses them to refuse new requests at once with a `503` when too much work to one service is already open. A fast refusal stops requests from piling up in a client while the service it calls is slow.

For HTTP/1 traffic, two settings form the circuit breaker. `tcp.maxConnections` caps the open connections, and `http.http1MaxPendingRequests` caps the queue of requests that wait for a connection. The proxy refuses a request only when both are full. If you set only `maxConnections`, the queue keeps its near-unlimited default, and extra requests wait instead of failing. For HTTP/2 and gRPC, one connection carries many requests, so `http2MaxRequests` is the setting that matters.

The limits count requests at the same time, not requests in total. A thousand requests sent one after another never trip `maxConnections: 1`. A real test uses a load generator with more parallel connections than the limit.

A circuit-breaker refusal has a clear signature. The access log line shows `503` with the `UO` (upstream overflow) response flag and `"-"` as the upstream host, and the `upstream_rq_pending_overflow` counter goes up. Per-cluster counters need the `sidecar.istio.io/statsInclusionPrefixes` annotation on the client pod. The application behind the Service never sees a refused request. A `503` without `UO` has another cause.

`istiod` sends the same limits to both ends. Each client proxy limits what it sends, and the proxy in each server pod limits what that pod accepts. `istioctl proxy-config cluster` shows the live thresholds under `circuitBreakers`, and any limit you did not set shows `4294967295`, which means no limit.

Retries interact with the circuit breaker in two ways. A client proxy never retries its own `UO` refusals. It does retry real `5xx` answers from the server, so a large `attempts` with `retryOn: 5xx` multiplies the load on a failing service. Keep `attempts` small, and use `connect-failure,refused-stream` to retry only requests that never reached the service.

Key facts to remember:

- `maxConnections` plus `http1MaxPendingRequests` is the HTTP/1 circuit breaker; `http2MaxRequests` is the HTTP/2 one.
- `UO` in the access log and `upstream_rq_pending_overflow` in the counters prove a circuit-breaker refusal.
- `upstream_cx_overflow` points at the connection limit; `upstream_rq_pending_overflow` points at the waiting queue.
- A connection pool caps open work at the same time; it is not rate limiting.
- `5xx` and `gateway-error` both retry a `503` from the server; `connect-failure,refused-stream` does not.

<!-- astrona:playground:destroy -->
