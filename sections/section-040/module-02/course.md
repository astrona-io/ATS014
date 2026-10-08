# Circuit Breaking With Connection Pool Limits

<!-- astrona:playground -->
> [!NOTE]
> 🧪 **Hands-on playground for this module** — a clean, throwaway machine to explore on. No task, no grading. Folder: `playground/`
>
> ```sh
> astrona run --git ssh://git@github.com/astrona-io/ATS014.git -c sections/section-040/module-02/playground
> astrona destroy ats-014-playground-040-02
> ```

Astronaut, a timeout protects one signal. A **circuit breaker** protects the calling ship itself while a service it depends on is struggling. It is the ship raising its shields.

Picture a big ship whose docking ports are already full. More ships keep arriving and circling, waiting for a docking port. Soon the whole sky around it is jammed, and ships that should be flying elsewhere are stuck in the queue. The safe move is to raise the shields early (close the hatch): tell new ships "no room, go somewhere else" right away.

That is what this module teaches. Without a limit, requests pile up inside the caller while they wait for a slow service. The caller's memory and workers fill up with work that will probably fail anyway. Then the caller gets slow too, and its own callers start to suffer. Nothing crashed, yet a whole chain of services is down.

Istio's answer is simple. You cap how much work a caller may have open to one service at the same time. Anything above that cap is refused **at once** with a 503. A fast, honest "no" is better than a slow one.

## How this module is organised

1. **[The Connection Pool](./course-01-the-connection-pool.md)** — the settings, which proxy enforces them, and the difference between "many requests at once" and "many requests in total". That difference decides whether your test proves anything.
2. **[Overflow And Its Signatures](./course-02-overflow-and-its-signatures.md)** — what the proxy does when a limit is full, and the two pieces of evidence that tell a circuit-breaker 503 apart from an application 503.
3. **[Scope, Verification And Retry Amplification](./course-03-scope-verification-and-retry-amplification.md)** — reading the live limits from a proxy, why the limits count per caller and not per service, and how retries can turn an overload into a storm.

The second half of circuit breaking, removing a pod that keeps failing, is the next module: [Outlier Detection And Endpoint Ejection](../module-03/course.md). That module's playground also holds the practice task that combines both halves.

## Learning objectives

After this module you can:

- Configure `trafficPolicy.connectionPool` with TCP and HTTP limits, and name what each setting caps.
- Explain which proxy enforces the limits, and why the backend never sees a rejected request.
- Explain why a limit on concurrency is not a limit on total requests, and design a test that actually trips it.
- Explain why `http1MaxPendingRequests` decides whether an HTTP/1 breaker trips at all.
- Identify a circuit-breaker rejection by the `UO` response flag and the `upstream_rq_pending_overflow` counter.
- Read the live limits out of a proxy with `istioctl proxy-config cluster`.
- Explain why connection pools are not server-side rate limiting, and what is.
- Describe how an aggressive retry policy turns a pool rejection into an overload spiral.

## Before you start

This module assumes [section 000](../../section-000/module-01/course.md). You should know that a proxy (the communications officer) runs beside every pod, that `istiod` (mission control) sends it its settings, and that `istioctl proxy-config` shows what a proxy really holds.

You also need `DestinationRule` and `trafficPolicy` from section 030. This module uses the same object and the same field, with different keys inside. Part 3 also uses the retry policy from [module 1](../module-01/course.md).

The playground gives you a training solar system: a `kind` cluster with **Istio 1.30.5** installed with Helm (`istio-base` and `istiod`, no gateways). Namespace **`bookinfo`** is labelled for sidecar injection and access logs are switched on for the whole mesh. It holds:

- `httpbin` — a small test server. Two pods (`httpbin-v1` and `httpbin-v2`) sit behind one Service on port `8000`.
- `fortio` — a load generator. It sends many requests **at the same time**. This module is all about requests at the same time, and `curl` in a loop only sends one at a time, so `fortio` is the tool here. Its pod has two containers, `fortio` and `istio-proxy`, so some commands need `-c fortio` or `-c istio-proxy` to pick one. Its sidecar is set up to keep the circuit-breaker counters that Part 2 reads.
- `curl` — a client pod for single requests.

There is **no `DestinationRule`** yet, so there is no limit at all.

Paste these helpers into your terminal once per session. The parts below use them. Each comment says what the helper does.

```sh
# 30 requests to httpbin over N parallel connections, from fortio; prints the status-code summary
load_test() { kubectl exec -n bookinfo deploy/fortio -c fortio -- \
  fortio load -c "$1" -qps 0 -n 30 -loglevel Warning http://httpbin:8000/get 2>&1 | grep -E "^Code"; }
# fortio's own circuit-breaker counters for httpbin
overflow_stats() { kubectl exec -n bookinfo deploy/fortio -c istio-proxy -- \
  pilot-agent request GET stats | grep 'httpbin.bookinfo' | grep -E 'pending_overflow|cx_overflow|pending_active'; }
```

The YAML files for this module are in the playground's [`examples/`](./playground/examples/) folder if you cloned the repository. The parts also show each one in full, written to a file before it is applied.

## Where this fits

Istio's own documentation groups two keys as "circuit breaking": `connectionPool` (this module) and `outlierDetection` ([module 3](../module-03/course.md)). They work as a pair. A connection pool refuses work you have no room for. Outlier detection stops sending work to one pod that keeps failing.

Module 1's retries sit awkwardly between them. A retry is extra work aimed at a service that just told you it was struggling. Part 3 is about that.
