# Fault Injection With Delays And Aborts

<!-- astrona:playground -->
> [!NOTE]
> 🧪 **Hands-on playground for this module** — a clean, throwaway machine to explore on. No task, no grading. Folder: [`playground/`](https://github.com/astrona-io/ATS014/tree/main/sections/section-050/module-01/playground)
>
> ```sh
> astrona run --git ssh://git@github.com/astrona-io/ATS014.git -c sections/section-050/module-01/playground
> astrona destroy ats-014-playground-050-01
> ```

Section 040 configured resilience. This section is how you find out whether any of it works.

A timeout you have never seen fire is a guess. A retry policy you have never watched retry is a guess. The usual ways to check are to wait for a real outage, which is a poor plan, or to add failure switches to the application, which means shipping test code to production.

Fault injection removes both. The proxy fabricates the failure: it holds a request for two seconds, or returns a 500 without contacting the upstream at all. The application under test is completely unmodified and cannot tell the difference — which is exactly what makes the result meaningful.

## How this module is organised

1. **[`fault.delay`](./course-01-fault-delay.md)** — making a dependency slow, where the fault is enforced, and which `VirtualService` it belongs on.
2. **[`fault.abort`](./course-02-fault-abort.md)** — making a dependency fail, why the upstream has no record of it, and sampling with `percentage`.
3. **[Scoping, Composition And Hazards](./course-03-scoping-composition-and-hazards.md)** — limiting a fault to your own requests, using injection to drive the section 040 features, finding a fault somebody left behind, and the module's pitfalls.

## Learning objectives

After this module you can:

- Inject `fault.delay` and `fault.abort` and say precisely what the caller experiences for each.
- Name which proxy enforces a fault and which `VirtualService` it belongs on.
- Explain why an aborted request leaves no trace in the destination's logs or metrics.
- Scope a fault to a fraction of traffic with `percentage`, and to specific requests with a `match`.
- Design injection experiments that exercise a timeout, a retry policy and outlier detection.
- Find a live or forgotten fault from the proxy configuration.
- Judge the risk of leaving a fault in a shared environment.

## Before you start

You need `VirtualService` routing and matching from section 010, and the `timeout` and `retries` fields from section 040 — a fault is most useful when there is something to point it at.

The playground gives you a single-node `kind` cluster with **Istio 1.30.5 already installed** (the `demo` profile) and the namespace **`fault-demo`**, injected, containing a two-hop call chain:

```text
throwaway curl pod  →  booking-service  →  notification-service
```

`booking-service` (port 80) calls `notification-service` on every `/book` request. That second hop is where the faults go, so you can watch a *service* react to a dependency failing rather than just watching curl react.

There is no permanent client pod in this namespace, so the commands below use `kubectl run --rm` to create a short-lived one. It lands in an injected namespace, so it gets a sidecar like anything else. No `VirtualService` exists yet.

## Where this fits

This is the test harness for section 040, and the two sections are best read as a pair. It also has a use beyond verifying configuration: injecting a dependency's failure is the cheapest way to find out what your application does when that dependency is down, which is usually less graceful than anyone expects. The same feature underpins chaos-engineering practice, with the important difference that here the blast radius is a field you control.
