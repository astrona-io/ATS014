# Part 1 — The Connection Pool

> Prerequisite: [the module landing page](./course.md). Next: [Part 2 — Overflow And Its Signatures](./course-02-overflow-and-its-signatures.md).

Four settings, two of which do the real work, and one distinction that determines whether any test you run means anything. This part covers the shape of the object and the mental model underneath it.

## The baseline: concurrency is currently free

`fortio load -c 2 -n 20` sends twenty requests with two in flight at any moment. `-qps 0` means "as fast as possible", so this is the most aggressive version of a small load.

> [!TIP]
> **Try it — twenty requests, two at a time, no policy**
>
> ```sh
> kubectl -n circuit-demo exec deploy/fortio -c fortio -- \
>   fortio load -c 2 -qps 0 -n 20 -loglevel Warning http://notification-service/notify
> ```
>
> Expect something like:
>
> ```text
> Code 200 : 20 (100.0 %)
> ```
>
> Twenty out of twenty. Nothing has set a ceiling, so the only limit is what the backend can serve.

## The object

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: notification-service
  namespace: circuit-demo
spec:
  host: notification-service
  trafficPolicy:
    connectionPool:
      tcp:
        maxConnections: 1
      http:
        http1MaxPendingRequests: 1
        maxRequestsPerConnection: 1
```

The four settings worth naming:

| Setting | Caps | Applies to |
| --- | --- | --- |
| `tcp.maxConnections` | concurrent upstream TCP connections | all protocols |
| `http.http1MaxPendingRequests` | requests queued waiting for a free connection | HTTP/1 |
| `http.http2MaxRequests` | concurrent requests on one connection | HTTP/2, where one connection multiplexes many |
| `http.maxRequestsPerConnection` | requests sent over a connection before it is replaced; `1` effectively disables keep-alive | HTTP/1 |

`tcp` also carries `connectTimeout` and TCP keepalive settings, which bound connection *establishment* rather than concurrency — useful, but not the circuit breaker.

## The queue model

The two settings that form the actual breaker for HTTP/1 traffic are `maxConnections` and `http1MaxPendingRequests`, and they describe a two-stage queue:

```text
   requests from the application
              │
              ▼
   ┌──────────────────────┐
   │  PENDING QUEUE       │   http1MaxPendingRequests: 1
   │  [ 1 slot ]          │   ── full? → reject immediately, 503 UO
   └──────────┬───────────┘
              │ a connection frees up
              ▼
   ┌──────────────────────┐
   │  CONNECTION POOL     │   tcp.maxConnections: 1
   │  [ 1 connection ]    │
   └──────────┬───────────┘
              ▼
          the backend
```

So with both set to 1: one request can be in flight, one more can wait, and a third simultaneous request has nowhere to go. It is rejected **on the spot** — not queued, not delayed. That immediacy is the feature. A request that cannot be served promptly is failed promptly, so the caller can shed it, serve a degraded response, or fail fast to *its* caller, rather than accumulating work.

## Two properties that are easy to get backwards

**It is enforced by the client.** The limits live in a `DestinationRule` describing a destination, but they are applied by the *calling* workload's sidecar before the request leaves. Three consequences:

- The backend never sees a rejected request, so looking for these 503s in the server's logs finds nothing.
- Every client enforces its own pool independently. Three callers each allowed one connection can have three connections open to the backend between them — so this is **not** server-side rate limiting.
- The limit protects the caller first. The backend benefits only as a side effect of callers refusing to pile on.

**It is about concurrency, not volume.** A thousand requests one after another never exceed `maxConnections: 1`, because only one is ever in flight. Three at once do.

Testing a circuit breaker sequentially and concluding it does not work is the single most common mistake on this topic, and it is why the playground ships `fortio` rather than expecting you to loop `curl`.

> [!TIP]
> **Try it — apply the limits, then stay inside them**
>
> ```sh
> kubectl apply -f - <<'EOF'
> apiVersion: networking.istio.io/v1
> kind: DestinationRule
> metadata:
>   name: notification-service
>   namespace: circuit-demo
> spec:
>   host: notification-service
>   trafficPolicy:
>     connectionPool:
>       tcp:
>         maxConnections: 1
>       http:
>         http1MaxPendingRequests: 1
>         maxRequestsPerConnection: 1
> EOF
> kubectl -n circuit-demo exec deploy/fortio -c fortio -- \
>   fortio load -c 1 -qps 0 -n 20 -loglevel Warning http://notification-service/notify
> ```
>
> Expect something like:
>
> ```text
> Code 200 : 20 (100.0 %)
> ```
>
> Twenty requests through a pool of one connection, all successful. The limit is in force and nothing was rejected, because at `-c 1` there was never more than one request in flight. This is exactly the result that fools people into thinking the policy did not apply.

## Breaking it

Raise the concurrency above the pool and the rejections appear immediately.

> [!TIP]
> **Try it — three concurrent callers against a pool of one**
>
> ```sh
> kubectl -n circuit-demo exec deploy/fortio -c fortio -- \
>   fortio load -c 3 -qps 0 -n 30 -loglevel Warning http://notification-service/notify
> ```
>
> Expect something like:
>
> ```text
> Code 200 : 19 (63.3 %)
> Code 503 : 11 (36.7 %)
> ```
>
> Your split will differ — it depends on timing, and on a fast local cluster requests complete quickly enough that many still get through. The 503s are the circuit breaker: requests that arrived with the one connection busy and the one pending slot already taken. Note the run finished in roughly the same wall-clock time as the successful one — rejection is not a delay.

> *`connectionPool` caps concurrent outstanding work per client, so a sequential test never trips it however many requests you send.*

## Reference

- [Circuit breaking task](https://istio.io/latest/docs/tasks/traffic-management/circuit-breaking/) — the upstream walkthrough, using the same `fortio` approach.
- [ConnectionPoolSettings API](https://istio.io/latest/docs/reference/config/networking/destination-rule/#ConnectionPoolSettings) — every TCP and HTTP field, including the timeouts.
- [Envoy circuit breaking](https://www.envoyproxy.io/docs/envoy/latest/intro/arch_overview/upstream/circuit_breaking) — the thresholds and what each one counts.
- `fortio load --help` — `-c`, `-n` and `-qps`, which are the three flags this module needs.
