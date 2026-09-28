# Circuit Breaking With Connection Pool Limits

<!-- astrona:playground -->
> [!NOTE]
> 🧪 **Hands-on playground for this module** — a clean, throwaway machine to explore on. No task, no grading. Folder: [`playground/`](https://github.com/astrona-io/ATS014/tree/main/sections/section-040/module-02/playground)
>
> ```sh
> astrona run --git ssh://git@github.com/astrona-io/ATS014.git -c sections/section-040/module-02/playground
> astrona destroy ats-014-playground-040-02
> ```

A timeout protects one request. Circuit breaking protects the caller's own health while a dependency is struggling — and, indirectly, the dependency itself.

The failure mode it prevents is queueing. A backend slows down; requests pile up in the caller waiting for a free connection; the caller's memory and worker pool fill with work that will probably time out anyway; the caller becomes unhealthy and takes down *its* callers. Nothing crashed, and a whole dependency chain is down.

Istio's answer is blunt and effective: cap how much concurrent work a caller may have outstanding to a given destination, and reject anything beyond that **immediately**. A fast, honest 503 beats a slow one.

## How this module is organised

1. **[The Connection Pool](./course-01-the-connection-pool.md)** — the four settings, which side enforces them, and the distinction that decides whether your test proves anything: concurrency versus volume.
2. **[Overflow And Its Signatures](./course-02-overflow-and-its-signatures.md)** — what the proxy does when a limit is exceeded, and the two pieces of evidence that tell a breaker 503 from an application 503.
3. **[Scope, Verification And Retry Amplification](./course-03-scope-verification-and-retry-amplification.md)** — reading the live thresholds, why the limits are per client rather than per service, and the interaction that turns an overload into a storm.

## Learning objectives

After this module you can:

- Configure `trafficPolicy.connectionPool` with TCP and HTTP limits, and name what each setting caps.
- Explain which proxy enforces the limits, and why the backend never sees a rejected request.
- Explain why a limit on concurrency is not a limit on total requests, and design a test that actually trips it.
- Identify a circuit-breaker rejection by the `UO` response flag and the `upstream_rq_pending_overflow` counter.
- Read the live thresholds out of a proxy with `istioctl proxy-config cluster`.
- Explain why connection pools are not server-side rate limiting, and what is.
- Describe how an aggressive retry policy turns a pool rejection into an overload spiral.

## Before you start

You need `DestinationRule` and `trafficPolicy` from section 030 — this is the same object and the same field with different keys underneath — and the retry policy from module 1, because Part 3 depends on it.

The playground gives you a single-node `kind` cluster with **Istio 1.30.5 already installed** (the `demo` profile) and the namespace **`circuit-demo`**, injected, containing:

- `notification-service` — the backend, behind a Service on port 80.
- `fortio` — a load generator. `curl` in a loop is sequential and this module is entirely about concurrency, so `fortio load -c <concurrency> -n <total>` is the tool. The pod has two containers, `fortio` and `istio-proxy`, so several commands below need `-c fortio` or `-c istio-proxy` to pick one.

No `DestinationRule` exists yet, so there is no limit at all.

## Where this fits

`connectionPool` and module 3's `outlierDetection` are the two keys Istio's own documentation groups together as "circuit breaking", and they are complementary: a connection pool refuses work you do not have capacity to do, while outlier detection stops sending work to an endpoint that keeps failing. Module 1's retries sit awkwardly between them, because a retry is extra concurrent work aimed at a service that just told you it was struggling. Part 3 is about that.
