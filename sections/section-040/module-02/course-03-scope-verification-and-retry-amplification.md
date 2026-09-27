# Part 3 — Scope, Verification And Retry Amplification

> Prerequisite: [Part 2 — Overflow And Its Signatures](./course-02-overflow-and-its-signatures.md). Next: [the module landing page](./course.md).

Three things remain: reading the thresholds the proxy is actually enforcing, being precise about what "per client" means for capacity planning, and the interaction with module 1 that turns a protective mechanism into a destructive one.

## The thresholds as Envoy holds them

Envoy's name for this feature is **circuit breakers**, and the configured thresholds sit on the cluster.

> [!TIP]
> **Try it — the thresholds the client proxy is enforcing**
>
> ```sh
> istioctl proxy-config cluster deploy/fortio -n circuit-demo \
>   --fqdn notification-service.circuit-demo.svc.cluster.local -o json | grep -A8 circuitBreakers
> ```
>
> Expect something like:
>
> ```text
> "circuitBreakers": {
>   "thresholds": [
>     {
>       "maxConnections": 1,
>       "maxPendingRequests": 1,
>       "maxRequests": 4294967295,
>       "maxRetries": 4294967295
> ```
>
> `maxConnections` and `maxPendingRequests` are your settings. The two enormous numbers are `2^32 - 1` — the unset defaults, meaning effectively no limit. That is the useful observation: **anything you do not configure is unbounded**, so a partial policy leaves a gap rather than inheriting something sensible.

`maxRequests` there corresponds to `http2MaxRequests`. On HTTP/1 traffic it does not bind, which is why the HTTP/1 breaker is built from `maxConnections` plus `maxPendingRequests`. On **HTTP/2** the picture inverts: one connection multiplexes many concurrent streams, so `maxConnections: 1` barely constrains anything and `http2MaxRequests` is the setting that matters. gRPC is HTTP/2, so this is not an edge case.

## "Per client" is a capacity statement

The limits are enforced in each calling workload's sidecar, over that sidecar's own counters. There is no shared state and no coordination.

```text
   caller A sidecar   maxConnections: 1  ──┐
   caller B sidecar   maxConnections: 1  ──┼──►  backend sees up to 3 connections
   caller C sidecar   maxConnections: 1  ──┘
```

Three consequences worth being able to state:

- **The backend's exposure is `limit × number of callers`**, not `limit`. Sizing a pool means knowing how many client pods there are, and remembering that number changes when the callers autoscale.
- **It is not rate limiting.** Rate limiting caps requests per unit time, globally, usually enforced server-side; a connection pool caps concurrent outstanding work, locally, per client. If a task says "the service must accept no more than N requests per second", a connection pool is the wrong answer.
- **A caller with no sidecar is unaffected.** Same caveat as the `Sidecar` resource in section 010 — this is client-side configuration, not an enforced boundary.

Where a genuine service-wide ceiling is required, Istio's answer is a rate limiting filter (local or global, backed by an external rate limit service), which is outside this module and outside the traffic-management domain.

## Retries and pools fight each other

This is the most valuable idea in the module, because it is a production trap rather than a syntax detail.

Work through the sequence:

```text
  1. backend slows down
  2. caller's pending queue fills
  3. pool rejects the overflow  →  503 with UO
  4. retryOn: 5xx sees a 5xx    →  RE-SENDS the request
  5. the retry occupies the same pool
  6. more overflow  →  more 503s  →  more retries …
```

The mechanism intended to absorb transient failures amplifies a sustained one. Each caller now generates `attempts + 1` times its normal concurrency at exactly the moment the pool is already full, and the pool rejections are themselves retriable under `5xx`.

Three defensive habits:

- **Prefer `gateway-error` or `connect-failure` over blanket `5xx`** on routes to a service you are also pool-limiting. A `503 UO` is a deliberate rejection, not a transient fault, and retrying it is counterproductive.
- **Keep `attempts` small** — one or two, not five.
- **Remember the budget from module 1.** A retry policy that cannot complete inside the route timeout produces a 504 *and* the extra load, which is the worst of both.

Istio does not stop you configuring the amplifying combination, and nothing warns you. It only shows up under load.

> [!TIP]
> **Try it — watch retries multiply the rejections**
>
> ```sh
> BEFORE=$(kubectl -n circuit-demo exec deploy/fortio -c istio-proxy -- \
>   pilot-agent request GET stats 2>/dev/null | grep 'notification-service.*pending_overflow' | awk -F': ' '{print $2}')
> kubectl apply -f - <<'EOF'
> apiVersion: networking.istio.io/v1
> kind: VirtualService
> metadata:
>   name: notification-service
>   namespace: circuit-demo
> spec:
>   hosts:
>     - notification-service
>   http:
>     - route:
>         - destination:
>             host: notification-service
>       retries:
>         attempts: 3
>         perTryTimeout: 1s
>         retryOn: 5xx
>       timeout: 10s
> EOF
> sleep 3
> kubectl -n circuit-demo exec deploy/fortio -c fortio -- \
>   fortio load -c 4 -qps 0 -n 40 -loglevel Warning http://notification-service/notify 2>&1 | grep -E 'Code |All done'
> AFTER=$(kubectl -n circuit-demo exec deploy/fortio -c istio-proxy -- \
>   pilot-agent request GET stats 2>/dev/null | grep 'notification-service.*pending_overflow' | awk -F': ' '{print $2}')
> echo "pending_overflow increased by: $((AFTER - BEFORE)) for 40 client requests"
> ```
>
> Expect something like:
>
> ```text
> Code 200 : 37 (92.5 %)
> Code 503 : 3 (7.5 %)
> pending_overflow increased by: 58 for 40 client requests
> ```
>
> Read those two numbers together. The client-visible failure rate *improved* — retries hid most of the rejections — while the proxy performed far more overflowing attempts than there were requests. Under real load that extra work is the spiral. Delete the `VirtualService` afterwards to leave the playground as you found it.

## Common pitfalls

> [!WARNING]
> **Testing sequentially.** `maxConnections` limits concurrency. A thousand requests one at a time never trip it, however long you run them.
>
> **Looking for the 503 in the server's logs.** The client proxy rejects the request and the backend never sees it. Look at the caller's access log for `UO`.
>
> **Confusing a breaker 503 with an application 503.** `UO` and `upstream_rq_pending_overflow` are what distinguish them. Neither moving means it is not a breaker.
>
> **Expecting the limits to protect the server globally.** Each client enforces its own pool, so the backend's exposure is `limit × callers`. For a service-wide ceiling you need rate limiting.
>
> **Leaving `http2MaxRequests` unset for HTTP/2 or gRPC traffic.** One connection carries many streams, so `maxConnections` barely constrains anything.
>
> **Assuming unset fields inherit something sensible.** They are `2^32 - 1` — unbounded.
>
> **Combining aggressive `retryOn: 5xx` with tight pools.** Retries turn an overload into a storm, and the client-visible failure rate can *improve* while the real load doubles.
>
> **Setting the pool on the server's own `DestinationRule` expecting server-side protection.** It is the caller's proxy that reads it.

> *Each caller enforces its own pool, so the limit you set is multiplied by the number of callers — and retries multiply it again.*

## Reference

- [Circuit breaking task](https://istio.io/latest/docs/tasks/traffic-management/circuit-breaking/) — the canonical walkthrough.
- [ConnectionPoolSettings API](https://istio.io/latest/docs/reference/config/networking/destination-rule/#ConnectionPoolSettings) — every field, with defaults.
- [Envoy circuit breaking](https://www.envoyproxy.io/docs/envoy/latest/intro/arch_overview/upstream/circuit_breaking) — the thresholds and the HTTP/1 versus HTTP/2 distinction.
- [Istio rate limiting](https://istio.io/latest/docs/tasks/policy-enforcement/rate-limit/) — what to use when the requirement is genuinely "no more than N per second".
