# Overflow And Its Signatures

Astronaut, a 503 on its own tells you very little. The application could have sent it. A pod could be unready. A route could lead nowhere. This part covers the two pieces of evidence that point to a circuit breaker and nothing else. That is the difference between finding an overload and chasing a bug in a backend that is working perfectly.

This part assumes the full limits from Part 1 are applied (`destinationrule-httpbin-connection-pool.yaml`).

## The `UO` response flag

Every sidecar keeps a black box flight log: one line per request, with a short code, called a **response flag**, that says how the request ended. Section 000 introduced them. This is the one that matters here:

> **`UO` — upstream overflow.** A circuit breaker refused the request.

An application's own 503 has no such flag. So the first question for any unexplained 503 is not "what is wrong with the backend?" It is "does the *caller's* access log say `UO`?"

> [!TIP]
> **Try it — the `UO` flag in the caller's access log**
>
> ```sh
> load_test 4 >/dev/null
> kubectl logs -n bookinfo deploy/fortio -c istio-proxy --tail=40 | grep ' UO ' | head -3
> ```
>
> Expect lines like this (trimmed):
>
> ```text
> "GET /get HTTP/1.1" 503 UO upstream_reset_before_response_started{overflow} ... "-" ...
> ```
>
> `503`, `UO` and `overflow` sit in the same line. Notice two things. This is the **caller's** proxy log, from `fortio`. And the upstream host is `"-"`: the request never left the caller.

The matching check is that the backend has no record of these requests.

> [!TIP]
> **Try it — `httpbin` never heard of the refused requests**
>
> ```sh
> CLIENT_UO=$(kubectl logs -n bookinfo deploy/fortio -c istio-proxy --tail=100 | grep -c ' 503 UO ')
> SERVER_503=$(kubectl logs -n bookinfo -l app=httpbin -c istio-proxy --tail=100 | grep -c ' 503 ')
> echo "client-side UO refusals: $CLIENT_UO"
> echo "server-side 503s:        $SERVER_503"
> ```
>
> Expect a number above zero on the first line and `0` on the second. The caller refused requests that `httpbin` never saw. This gap proves the limit is enforced by the caller. It is also why a report that "the service is returning 503s" can be wrong about *which* service is involved.

## The overflow counters

Access logs roll over. Counters keep adding up. For anything after the fact, the Envoy statistics are better evidence, and they also tell you *which* limit was hit.

You reach a sidecar's statistics with `pilot-agent request`. It is a small tool inside every Istio proxy container that talks to the proxy's local administration page. Read the name as **pilot** (the old name for `istiod`) + **agent**. `request GET stats` asks the proxy for its counters.

The counters to know. Each one starts with the cluster name, for example `cluster.outbound|8000||httpbin.bookinfo.svc.cluster.local`:

| Counter | Goes up when |
| --- | --- |
| `upstream_rq_pending_overflow` | a request was refused because the **waiting queue** was full |
| `upstream_cx_overflow` | the **connection** limit was reached |
| `upstream_rq_retry_overflow` | a retry was refused because the retry budget was used up |
| `upstream_rq_pending_active` | requests waiting right now (a live value, not a running total) |

`upstream_rq_pending_overflow` is the one to name if someone asks how to prove a circuit breaker tripped.

### One step before the counters exist

A stock Istio sidecar does not export these counters. Istio keeps only a small set of Envoy counters by default, and per-cluster counters like the ones above are not in it. Ask an unchanged proxy with `pilot-agent request GET stats` and the `grep` comes back empty. That looks exactly like "the breaker never tripped".

You add them back per workload with an annotation on the **pod template** of the *caller*, because the breaker lives in the caller's proxy:

```yaml
template:
  metadata:
    annotations:
      sidecar.istio.io/statsInclusionPrefixes: "cluster.outbound"
```

The playground's `fortio` Deployment already has it. On your own cluster, remember that it is a pod annotation. Changing it restarts the pod, and the counters start again from zero.

> [!TIP]
> **Try it — the overflow counters**
>
> ```sh
> load_test 3 >/dev/null
> overflow_stats
> ```
>
> Expect three lines in this shape (your numbers will differ):
>
> ```text
> cluster.outbound|8000||httpbin.bookinfo.svc.cluster.local;.upstream_cx_overflow: <count>
> cluster.outbound|8000||httpbin.bookinfo.svc.cluster.local;.upstream_rq_pending_active: 0
> cluster.outbound|8000||httpbin.bookinfo.svc.cluster.local;.upstream_rq_pending_overflow: <count>
> ```
>
> `pending_overflow` counts requests refused for lack of a waiting slot. `cx_overflow` counts the times the connection limit itself was the problem. `pending_active` is `0` because nothing is in flight while you read it. All of these add up from the moment the proxy started, so note the values before a run if you want a per-run number.

## Reading the numbers together

The two overflow counters answer different questions. Together they tell you which limit to change:

- **`pending_overflow` high, `cx_overflow` low:** requests arrive faster than the one connection can clear them. Raising `http1MaxPendingRequests` buys more waiting room. Raising `maxConnections` buys more throughput.
- **`cx_overflow` high:** the connection limit is the bottleneck. Raise `maxConnections`.
- **Both zero while you see 503s:** it is not a circuit breaker. Look at the backend, the route, or the endpoint list.

That last line is the useful one in an exam. A 503 with no `UO` flag and no movement in the overflow counters is somebody else's problem.

## Common pitfalls

> [!WARNING]
> **Looking for an overflow 503 at the backend.** The backend never saw the request. All the evidence is in the caller's proxy log and counters.
>
> **Reading a bare 503 as a circuit breaker.** Without the `UO` flag it is something else: an application error, an unready pod, or a route with no endpoints.
>
> **Relying on access logs after the fact.** They roll over. `upstream_rq_pending_overflow` keeps adding up and is the counter to quote.
>
> **Mixing up `upstream_cx_overflow` and `upstream_rq_pending_overflow`.** The first is the connection limit, the second the waiting queue. They point at different settings.
>
> **Forgetting the stats annotation.** Without `sidecar.istio.io/statsInclusionPrefixes` on the caller, the per-cluster counters are simply not there.
>
> **Expecting counters before any traffic.** A cluster's counters appear once the proxy has had a reason to create them.

> *`UO` in the caller's access log and `upstream_rq_pending_overflow` in its stats are what set a breaker refusal apart from an application 503, and the backend's silence confirms it.*
