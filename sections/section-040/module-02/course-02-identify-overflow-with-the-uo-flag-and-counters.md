# Identify Overflow With The UO Flag And Counters

A `503` (Service Unavailable) on its own tells you very little. The application could have sent it. A pod could be unready. A route could lead to a Service with no pods. This part shows the two pieces of evidence that point to the circuit breaker and nothing else: the `UO` flag in the access log and the overflow counters in the proxy. They are the difference between finding an overload and chasing a bug in an application that works perfectly.

## The `UO` response flag

Every sidecar proxy (Envoy) can write an **access log**: one line per request, with a short code called a **response flag** that says how the request ended. The playground has access logs switched on for every proxy. This is the flag that matters here:

> **`UO`, upstream overflow.** The proxy refused the request because a connection pool limit was full.

An application's own `503` has no such flag. So the first question for any unexplained `503` is not "what is wrong with the probe?". It is "does the access log of the **client** proxy say `UO`?".

The commands below need two things in the playground. The first is the `probe` `DestinationRule` with `tcp.maxConnections`, `http.http1MaxPendingRequests` and `http.maxRequestsPerConnection` all set to `1`, saved and applied as `destinationrule-probe-connection-pool.yaml`. The second is two shell helpers: `load_test` sends 30 requests from `fortio` over a given number of parallel connections, and `overflow_stats` reads `fortio`'s circuit-breaker counters for the `probe` Service. Paste them into your terminal:

<!-- astrona:playground:renew -->

```sh
# 30 requests to the probe over N parallel connections, from fortio; prints the status-code summary
load_test() { kubectl exec -n starfleet deploy/fortio -c fortio -- \
  fortio load -c "$1" -qps 0 -n 30 -loglevel Warning http://probe:8000/get 2>&1 | grep -E "^Code"; }
# fortio's own circuit-breaker counters for the probe
overflow_stats() { kubectl exec -n starfleet deploy/fortio -c istio-proxy -- \
  pilot-agent request GET stats 2>/dev/null | grep 'probe.starfleet' | grep -E 'pending_overflow|cx_overflow|pending_active'; }
```

Now send 30 requests, 4 at a time, and keep only the access log lines of `fortio`'s proxy that say `UO`:

```sh
load_test 4 >/dev/null
kubectl logs -n starfleet deploy/fortio -c istio-proxy --tail=40 | grep ' UO ' | head -2
```

You should see lines like these (shortened):

```text
"GET /get HTTP/1.1" 503 UO upstream_reset_before_response_started{overflow} ... "probe:8000" "-" outbound|8000||probe.starfleet.svc.cluster.local ...
"GET /get HTTP/1.1" 503 UO upstream_reset_before_response_started{overflow} ... "probe:8000" "-" outbound|8000||probe.starfleet.svc.cluster.local ...
```

`503`, `UO` and `overflow` sit on the same line. Two details matter. This is the access log of the **client** proxy, in the `fortio` pod. And the upstream host field, right after `"probe:8000"`, is `"-"`: the proxy never chose a `probe` pod, so the request never left the `fortio` pod.

## Count the refusals on both sides

The client proxy is not the only place that can refuse a request. Compare the `UO` refusals in `fortio`'s proxy with the `503`s that the proxies in the `probe` pods logged themselves:

```sh
SENDER_UO=$(kubectl logs -n starfleet deploy/fortio -c istio-proxy --tail=100 | grep -c ' 503 UO ')
PROBE_503=$(kubectl logs -n starfleet -l app=probe -c istio-proxy --tail=100 | grep -c ' 503 ')
echo "sender-side UO refusals: $SENDER_UO"
echo "probe-side 503s:         $PROBE_503"
```

You should see something like:

```text
sender-side UO refusals: 20
probe-side 503s:         1
```

Nearly every refusal happened in the client proxy, and the `probe` pods never received those requests. The few `503`s in the `probe` proxies' own logs are not application errors either. Look at one:

```sh
kubectl logs -n starfleet -l app=probe -c istio-proxy --tail=100 | grep ' 503 '
```

```text
"GET /get HTTP/1.1" 503 UO upstream_reset_before_response_started{overflow} ... "probe:8000" "-" inbound|8080|| ...
```

It is also `UO`, but on the `inbound` side: the sidecar proxy in the `probe` pod refused the request when it arrived, because the same limits apply on both ends. Either way, the `probe` application never saw a refused request. That gap is also why a report that "the probe is returning `503`s" can be wrong about *which* component refused the request.

## The overflow counters

Access logs roll over, while counters keep adding up. For anything after the fact, the counters are better evidence, and they also tell you *which* limit was hit.

You read them with `pilot-agent request`, a small tool inside every Istio proxy container that talks to the proxy's local administration interface. `request GET stats` asks the proxy for its counters. Each counter name starts with the Envoy cluster name, here `cluster.outbound|8000||probe.starfleet.svc.cluster.local`. An Envoy **cluster** is the proxy's name for one destination service and the pods behind it.

| Counter | Goes up when |
| --- | --- |
| `upstream_rq_pending_overflow` | a request was refused because the **waiting queue** was full |
| `upstream_cx_overflow` | the **connection** limit was reached |
| `upstream_rq_pending_active` | requests waiting right now (a live value, not a running total) |

`upstream_rq_pending_overflow` is the counter to name when someone asks how to prove that the circuit breaker tripped.

A standard Istio sidecar proxy does not keep these counters. It keeps only a small set by default, and per-cluster counters like these are not in it, so the `grep` comes back empty. That looks exactly like "the circuit breaker never tripped". You add the counters for one workload with an annotation on the **client's** pod template:

```yaml
template:
  metadata:
    annotations:
      sidecar.istio.io/statsInclusionPrefixes: "cluster.outbound"
```

The `fortio` Deployment in the playground already has this annotation. Changing it restarts the pod, and the counters start again from zero. Send another 30 requests, 3 at a time, then read the counters:

```sh
load_test 3 >/dev/null
overflow_stats
```

You should see three lines in this form (your numbers will be different):

```text
cluster.outbound|8000||probe.starfleet.svc.cluster.local;.upstream_cx_overflow: 157
cluster.outbound|8000||probe.starfleet.svc.cluster.local;.upstream_rq_pending_active: 0
cluster.outbound|8000||probe.starfleet.svc.cluster.local;.upstream_rq_pending_overflow: 109
```

`upstream_rq_pending_overflow` counts requests refused because no waiting slot was free. `upstream_cx_overflow` counts the times the connection limit itself was reached. `upstream_rq_pending_active` is `0` because no request is open while you read it. The two overflow counters add up from the moment the proxy started, so note the values before a run if you want the number for one run.

## Reading the numbers together

The two overflow counters answer different questions. Together they tell you which limit to change:

- **`upstream_rq_pending_overflow` high:** requests arrive faster than the open connections can finish them. Raising `http1MaxPendingRequests` gives more waiting room. Raising `maxConnections` gives more throughput.
- **`upstream_cx_overflow` high:** the connection limit is the bottleneck. Raise `maxConnections`.
- **Both unchanged while you see `503`s:** the circuit breaker did not cause them. Look at the application, the route, or the list of pods behind the Service.

> [!TIP]
> When you see an unexplained `503`, read the response flag in the **client** proxy's access log first. `UO` means the connection pool refused it. No flag means the cause is somewhere else.

You can now prove a circuit-breaker refusal in two ways: the `UO` flag with `"-"` as the upstream host in the access log, and a rising `upstream_rq_pending_overflow` counter. You also saw that a few refusals happen in the `probe` pods' own proxies. Which limits each proxy really holds, and how retries behave on top of them, is still open.

## Common pitfalls

> [!WARNING]
> - **Looking for a refused request in the probe application.** The application never saw it. The evidence is in the access logs and counters of the proxies.
> - **Reading a bare `503` as the circuit breaker.** Without the `UO` flag it is something else: an application error, an unready pod, or a route to a Service with no pods.
> - **Relying on access logs after the fact.** They roll over. `upstream_rq_pending_overflow` keeps adding up.
> - **Mixing up `upstream_cx_overflow` and `upstream_rq_pending_overflow`.** The first is the connection limit, the second the waiting queue. They point at different settings.
> - **Forgetting the stats annotation.** Without `sidecar.istio.io/statsInclusionPrefixes` on the client pod, the per-cluster counters are not there.

## Your mission: Configure And Prove A Connection Pool Circuit Breaker Lab

You can now set connection pool limits, trip them on purpose, and prove a refusal with the `UO` flag and the overflow counters. The lab asks you to limit how much work a client may have open to a backend, and to prove that the limit refuses requests sent at the same time but never requests sent one by one. The lab uses its own small app (`notification-service` and `fortio` in the `circuit-demo` namespace), not the Starfleet.

The lab runs in its own cluster, so first pause your playground. Nothing in it is lost:

```sh
astrona stop ats-014-playground-040-02
```

Then start the lab:

```sh
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-040/module-02/labs/lab-01
```

The task is on the next page. Solve it on your own first. When you think you are done, send it for grading:

```sh
astrona submit -c sections/section-040/module-02/labs/lab-01
```

When the lab is done, remove it and start your playground again:

```sh
astrona destroy ats-014-lab-040-02
astrona start ats-014-playground-040-02
```
