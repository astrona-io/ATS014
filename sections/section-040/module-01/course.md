# Timeouts And Retries

<!-- astrona:playground -->
> [!NOTE]
> 🧪 **Hands-on playground for this module** — a clean, throwaway machine to explore on. No task, no grading. Folder: [`playground/`](https://github.com/astrona-io/ATS014/tree/main/sections/section-040/module-01/playground)
>
> ```sh
> astrona run --git ssh://git@github.com/astrona-io/ATS014.git -c sections/section-040/module-01/playground
> astrona destroy ats-014-playground-040-01
> ```

A service that is merely slow can take down everything that calls it. Each caller holds a connection open, waiting; those callers have callers of their own, also waiting; and a single unresponsive pod becomes a cluster-wide stall without a process crashing anywhere. The fix is not more capacity. It is a deadline.

Retries are the same idea from the other side: some failures are transient, and giving up on the first attempt throws away requests that would have succeeded a moment later. Istio can retry without the application knowing.

The two interact, and that interaction is the most reliably examined detail in this module:

> The route `timeout` is the whole budget **including** retries, so a timeout shorter than `attempts` × `perTryTimeout` silently truncates the retries.

## How this module is organised

1. **[Part 1 — The Route Timeout](./course-01-the-route-timeout.md)** — where the deadline is measured, what the caller receives when it expires, and what a timeout does *not* do.
2. **[Part 2 — The Retry Policy](./course-02-the-retry-policy.md)** — `attempts`, `perTryTimeout` and `retryOn`, the off-by-one in `attempts`, and the retry policy Istio applies when you configure nothing.
3. **[Part 3 — The Shared Budget And Idempotency](./course-03-the-shared-budget-and-idempotency.md)** — the budget arithmetic, the `UT` response flag, switching retries off properly, and why a retried `POST` is your problem.

## Learning objectives

After this module you can:

- Set a route `timeout`, say which proxy measures it, and name the status the caller receives.
- Explain why a timeout protects the caller but does not stop the upstream's work.
- Configure `retries` with `attempts`, `perTryTimeout` and `retryOn`, and name the common retry conditions.
- Read `attempts` correctly as the number of retries *after* the first try.
- State Istio's implicit default retry policy and how to genuinely switch retries off.
- Calculate the timeout budget a retry policy needs, and recognise a truncated retry from a 504 and the `UT` flag.
- Prove how many attempts really happened from the server-side access log.
- Decide when retries are unsafe, and scope them away from non-idempotent routes.

## Before you start

You need `VirtualService` from section 010. Both settings here are extra fields on an HTTP route you already know how to write — no new object is introduced.

The playground gives you a single-node `kind` cluster with **Istio 1.30.5 already installed** (the `demo` profile) and the namespace **`resilience-demo`**, injected, containing:

- `httpbin` — a service with two endpoints that make failure controllable: `/delay/<seconds>` sleeps before answering, and `/status/<code>` returns exactly that status immediately. Both on port 8000.
- `tester` — a client pod with `curl`.

No `VirtualService` exists yet, so there is no route timeout at all.

## Where this fits

This is the first of section 040's four modules, and the other three are the same idea applied to different failure shapes: connection pools cap how much concurrent work a caller may have outstanding, outlier detection removes endpoints that keep failing, and locality settings decide where traffic goes when a whole zone is unhealthy. Timeouts and retries come first because they are the ones that interact with everything else — retries can overwhelm a connection pool, and they can hide the failures outlier detection needs to see.
