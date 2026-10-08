# Timeouts And Retries

<!-- astrona:playground -->
> [!NOTE]
> 🧪 **Hands-on playground for this module** — a clean, throwaway machine to explore on. No task, no grading. Folder: `playground/`
>
> ```sh
> astrona run --git ssh://git@github.com/astrona-io/ATS014.git -c sections/section-040/module-01/playground
> astrona destroy ats-014-playground-040-01
> ```

Astronaut, picture a convoy of spaceships passing signals down a line. If one ship stops answering, the ship that called it waits with its radio channel open. That ship's own callers wait too. One stuck pod can stall a whole chain of services, and nothing crashes anywhere. More ships do not fix this. A deadline does.

A **timeout** is that deadline. Think of it as a mission's abort window: if no answer has come back by then, the call is called off and the caller gets an error instead of waiting forever.

**Retries** are the same idea from the other side. Many failures only last a moment: a pod restarts, or a connection drops. A retry is re-sending a signal that got lost in space. Istio can do it for you, without the app knowing.

The two settings work together, and that is the detail exams like to test most:

> The route `timeout` is the budget for the **whole** request, **including** all retries. A timeout shorter than (`attempts` + 1) × `perTryTimeout` quietly cuts the retries short.

## How this module is organised

1. **[The Route Timeout](./course-01-the-route-timeout.md)** — which proxy measures the deadline, what the caller gets when it runs out, how to test a timeout with an injected delay, and what a timeout does *not* do.
2. **[The Retry Policy](./course-02-the-retry-policy.md)** — `attempts`, `perTryTimeout` and `retryOn`, the off-by-one in `attempts`, the `URX` flag, and the retry policy Istio uses when you set nothing.
3. **[The Shared Budget And Idempotency](./course-03-the-shared-budget-and-idempotency.md)** — the budget arithmetic, per-try timeouts, how to read both values off the proxy, and why a retried `POST` is your problem.

## Learning objectives

After this module you can:

- Set a route `timeout`, say which proxy measures it, and name the status the caller receives.
- Test a timeout by putting a delay on the called service and the timeout on the caller, and explain why the two cannot share one route.
- Explain why a timeout protects the caller but does not stop the upstream's work.
- Configure `retries` with `attempts`, `perTryTimeout` and `retryOn`, and choose between `5xx`, `gateway-error` and an exact status code.
- Read `attempts` correctly as the number of retries *after* the first try.
- State Istio's default retry policy and how to switch retries off for real.
- Calculate the timeout budget a retry policy needs, and recognise cut-off retries from a 504 with the `UT` flag and used-up retries from the `URX` flag.
- Prove how many attempts really happened from the server-side access log.
- Decide when retries are unsafe, and keep them away from routes that are not safe to repeat.

## Before you start

This module assumes [section 000](../../section-000/module-01/course.md): a sidecar proxy (the communications officer) beside every pod, `istiod` (mission control) sending it settings, and `istioctl proxy-config` as the way to see what a proxy really holds.

You need `VirtualService` from section 010. Both settings here are extra fields on an HTTP route you already know how to write. No new object is introduced.

The playground gives you a training solar system: a single-node `kind` cluster with **Istio 1.30.5** installed with Helm (`istio-base` and `istiod`), access logs switched on, and the namespace **`bookinfo`**, labelled for sidecar injection. In it:

- **Bookinfo**: `productpage`, `details`, `ratings` and `reviews` v1, v2 and v3 on port 9080. Only `reviews` v2 and v3 call `ratings`, which matters when you test a timeout across two services.
- **`httpbin`** v1 and v2 behind one Service on port 8000. It fails on demand: `/delay/<seconds>` waits before it answers, and `/status/<code>` answers with exactly that status. `/status/200,503` picks one of the two at random.
- **`curl`**, a client pod inside the mesh.
- The `reviews` subsets, and a route that sends `end-user: jason` to `reviews` v2.

There is no timeout and no retry rule yet. The files for every step are in the playground's `examples/` folder.

Paste these two helpers into your terminal before the first "Try it". Every part uses them:

```sh
status_and_time() { kubectl exec -n bookinfo deploy/curl -- curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" "$@"; }
count_received() { sleep 4; kubectl logs -n bookinfo -l app=httpbin -c istio-proxy --since=${2:-8s} | grep -c "$1"; }
```

`status_and_time` sends one request and prints the status code and the time it took. `count_received` counts how many requests the `httpbin` pods really received, from their sidecar logs.

## Where this fits

This is the first of section 040's four modules. The other three apply the same idea to different kinds of failure: connection pools limit how much work a caller may have waiting, outlier detection removes endpoints that keep failing, and locality settings decide where traffic goes when a whole zone is unhealthy. Timeouts and retries come first because they affect all the others. Retries can overload a connection pool, and they can hide the failures that outlier detection needs to see.
