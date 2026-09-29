# Overflow And Its Signatures

> Prerequisite: [The Connection Pool](./course-01-the-connection-pool.md). Next: [Scope, Verification And Retry Amplification](./course-03-scope-verification-and-retry-amplification.md).

A 503 on its own is ambiguous — the application could have produced it, a pod could be unready, a route could resolve to nothing. This part is about the two pieces of evidence that identify a circuit-breaker rejection specifically, which is the difference between diagnosing an overload and chasing a bug in a backend that is behaving perfectly.

## The `UO` response flag

Envoy stamps every access log line with response flags describing how the request ended. Part 1 of module 1 introduced them; this is the one that matters here:

> **`UO` — upstream overflow.** The request was rejected by a circuit breaker.

An application 503 carries no such flag. So the first question for any unexplained 503 is not "what is wrong with the backend" but "does the caller's access log say `UO`".

> [!TIP]
> **Try it — the `UO` flag in the caller's access log**
>
> ```sh
> kubectl -n circuit-demo exec deploy/fortio -c fortio -- \
>   fortio load -c 4 -qps 0 -n 40 -loglevel Warning http://notification-service/notify >/dev/null 2>&1
> kubectl -n circuit-demo logs deploy/fortio -c istio-proxy --tail=40 | grep UO | head -3
> ```
>
> Expect something like:
>
> ```text
> [2026-09-27T11:41:09.882Z] "GET /notify HTTP/1.1" 503 UO upstream_reset_before_response_started{overflow} - "-" 0 81 0 - "-" "fortio.org/fortio-1.60.3" ...
> ```
>
> `503 UO` and `overflow` in the same line. Note two things: this is the **client's** proxy log, and the duration field near the end is `0` — the request spent no time upstream because it never went there.

The complementary check is the absence of evidence at the backend.

> [!TIP]
> **Try it — the backend has no record of the rejected requests**
>
> ```sh
> CLIENT_503=$(kubectl -n circuit-demo logs deploy/fortio -c istio-proxy --tail=100 | grep -c ' 503 UO ')
> SERVER_503=$(kubectl -n circuit-demo logs -l app=notification-service -c istio-proxy --tail=100 | grep -c ' 503 ')
> echo "client-side UO rejections: $CLIENT_503"
> echo "server-side 503s:          $SERVER_503"
> ```
>
> Expect something like:
>
> ```text
> client-side UO rejections: 23
> server-side 503s:          0
> ```
>
> Twenty-three rejections that the backend never heard about. This asymmetry is the proof that the limit is enforced on the calling side — and the reason a "the service is returning 503s" report can be completely wrong about which service is involved.

## The overflow counters

Access logs roll over; counters accumulate. For anything after the fact, the Envoy statistics are better evidence, and they distinguish *which* limit was hit.

You reach a sidecar's admin statistics through `pilot-agent request`, a small client for the proxy's local admin API present in every Istio proxy container. Read it as **pilot** (the old name for the control plane the agent talks to) + **agent**; `request GET stats` performs a GET against the proxy's own admin endpoint.

The counters to know, all prefixed with the cluster name:

| Counter | Incremented when |
| --- | --- |
| `upstream_rq_pending_overflow` | a request was rejected because the **pending queue** was full |
| `upstream_cx_overflow` | the **connection** limit was reached |
| `upstream_rq_retry_overflow` | a retry was rejected because the retry budget was exhausted |
| `upstream_rq_pending_active` | requests currently waiting (a gauge, not a counter) |

`upstream_rq_pending_overflow` is the one to name if you are asked how to prove a circuit breaker tripped.

### One thing to do before the counters exist

A stock Istio sidecar does not export them. Istio installs a stats filter that
keeps a small set of Envoy counters — control-plane and listener health, mostly —
and per-cluster counters like the ones above are not in that set. Query
`pilot-agent request GET stats` on an unmodified proxy and the grep comes back
empty, which looks exactly like "the breaker never tripped".

Add them back per workload with an annotation on the **pod template** of the
client — the caller, since the breaker lives in the caller's proxy:

```yaml
template:
  metadata:
    annotations:
      sidecar.istio.io/statsInclusionPrefixes: "cluster.outbound"
```

The playground and the lab for this module already carry it on the client
workload. On your own cluster, remember it is a pod annotation: changing it
restarts the pod, and the counters start from zero again.

> [!TIP]
> **Try it — the overflow counters**
>
> ```sh
> kubectl -n circuit-demo exec deploy/fortio -c istio-proxy -- \
>   pilot-agent request GET stats | grep notification-service | grep -E 'pending_overflow|cx_overflow|pending_active'
> ```
>
> Expect something like:
>
> ```text
> cluster.outbound|80||notification-service.circuit-demo.svc.cluster.local;.upstream_cx_overflow: 9
> cluster.outbound|80||notification-service.circuit-demo.svc.cluster.local;.upstream_rq_pending_active: 0
> cluster.outbound|80||notification-service.circuit-demo.svc.cluster.local;.upstream_rq_pending_overflow: 37
> ```
>
> Thirty-seven requests rejected for lack of a pending slot, and nine occasions where the connection limit itself was the binding constraint. `pending_active: 0` because nothing is in flight while you read it. These are cumulative since the proxy started, so take a baseline if you want a per-run number.

## Reading the numbers together

The two counters answer different questions, and the ratio tells you which limit to change:

- **`pending_overflow` high, `cx_overflow` low** — requests are arriving faster than the single connection can drain them. Raising `http1MaxPendingRequests` buys queueing; raising `maxConnections` buys throughput.
- **`cx_overflow` high** — the connection limit is the binding constraint. Raise `maxConnections`.
- **Both zero while you are seeing 503s** — it is not a circuit breaker. Look at the backend, the route, or the endpoint list.

That last line is the useful one on an exam. A 503 with no `UO` and no overflow counter movement is somebody else's problem.

## Common pitfalls

> [!WARNING]
> **Diagnosing an overflow 503 at the backend.** The backend never saw the request. The evidence is entirely in the caller's proxy log and counters.
>
> **Reading a bare 503 as a circuit breaker.** Without the `UO` flag it is something else — an application error, an unready pod, or a route with no endpoints.
>
> **Relying on access logs after the fact.** They roll over. `upstream_rq_pending_overflow` accumulates and is the counter to quote.
>
> **Confusing `upstream_cx_overflow` with `upstream_rq_pending_overflow`.** The first is the connection limit, the second the pending queue. They point at different settings.
>
> **Expecting counters to exist before any traffic.** A cluster's statistics appear once the proxy has had a reason to create them.

> *`UO` in the access log and `upstream_rq_pending_overflow` in the stats are what distinguish a breaker rejection from an application 503 — and the backend's silence confirms it.*

## Reference

- [Envoy response flags](https://www.envoyproxy.io/docs/envoy/latest/configuration/observability/access_log/usage#config-access-log-format-response-flags) — `UO` and the rest of the list.
- [Envoy cluster statistics](https://www.envoyproxy.io/docs/envoy/latest/configuration/upstream/cluster_manager/cluster_stats) — every `upstream_*` counter, with what increments it.
- [Circuit breaking task](https://istio.io/latest/docs/tasks/traffic-management/circuit-breaking/) — the same counters, in the upstream walkthrough.
- `pilot-agent request GET stats` — run inside any `istio-proxy` container; add `?filter=<regex>` to narrow it server-side.
