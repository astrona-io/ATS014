# Fault Injection With Delays And Aborts

<!-- astrona:playground -->
> [!NOTE]
> 🧪 **Hands-on playground for this module** — a clean, throwaway machine to explore on. No task, no grading. Folder: `playground/`
>
> ```sh
> astrona run --git ssh://git@github.com/astrona-io/ATS014.git -c sections/section-050/module-01/playground
> astrona destroy ats-014-playground-050-01
> ```

Astronaut, section 040 fitted your ships with resilience. This module is the simulation drill that tells you whether any of it works.

A timeout you have never seen fire is a guess. A retry policy you have never watched retry is a guess. The usual ways to check are to wait for a real outage, which is a poor plan, or to add failure switches to the application, which means shipping test code to production.

Fault injection removes both. The proxy fabricates the failure: it holds a request for two seconds, or returns a 500 without contacting the upstream at all. The application under test is completely unmodified and cannot tell the difference — which is exactly what makes the result meaningful.

Think of it as a simulation drill. Mission control fakes an engine failure on purpose, so the crew can practise the response while nothing is really at stake. Here the "fake failure" is a few lines of YAML, the crew is your application, and the failure is a signal that arrives late or never arrives at all.

## How this module is organised

1. **[`fault.delay`](./course-01-fault-delay.md)** — making a dependency slow, where the fault is enforced, and which `VirtualService` it belongs on.
2. **[`fault.abort`](./course-02-fault-abort.md)** — making a dependency fail, why the upstream has no record of it, and sampling with `percentage`.
3. **[Scoping, Composition And Hazards](./course-03-scoping-composition-and-hazards.md)** — limiting a fault to your own requests or to one calling service, using injection to drive the section 040 features, finding a fault somebody left behind, and the module's pitfalls.

## Learning objectives

After this module you can:

- Inject `fault.delay` and `fault.abort` and say precisely what the caller experiences for each.
- Name which proxy enforces a fault and which `VirtualService` it belongs on.
- Explain why an aborted request leaves no trace in the destination's logs or metrics, and spot injected faults by their `FI` and `DI` response flags.
- Scope a fault to a fraction of traffic with `percentage`, to specific requests with a `match`, and to one calling service with `sourceLabels`.
- Design injection experiments that exercise a timeout, a retry policy and outlier detection.
- Find a live or forgotten fault from the proxy configuration.
- Judge the risk of leaving a fault in a shared environment.

## Before you start

This module assumes [section 000](../../section-000/module-01/course.md): a proxy beside every pod, `istiod` programming it over xDS, and `istioctl proxy-config` as the way to see what a proxy actually holds rather than what you hoped it holds.

You need `VirtualService` routing and matching from section 010, and the `timeout` and `retries` fields from section 040 — a fault is most useful when there is something to point it at.

The playground is a training solar system in the simulator: a single-node `kind` cluster with **Istio 1.30.5** installed by Helm (`istio-base` and `istiod`, no gateways) and access logs turned on. Namespace **`bookinfo`** holds the Bookinfo sample app, the same one the Istio fault injection task uses, plus a `curl` client pod. Every pod is injected. The call chain the faults go into is:

```text
curl pod  →  reviews (v2 or v3)  →  ratings
```

`reviews` v2 and v3 call `ratings` on every request; `reviews` v1 does not. That second hop is where most faults go, so you can watch a *ship* react when a ship it depends on fails, rather than just watching curl react. `reviews` also passes the `end-user` header on to `ratings`, which is what lets a fault target one user.

The playground already defines the subsets `reviews` v1/v2/v3 and `ratings` v1 in DestinationRules. No `VirtualService` exists yet. The playground's [overview](./playground/docs/overview.md) has two helper functions, `status_and_time` and `count_ratings_status`, that the "Try it" steps in every part use. Paste them into your terminal once.

## Where this fits

This is the test harness for section 040, and the two sections are best read as a pair. It also has a use beyond verifying configuration: injecting a dependency's failure is the cheapest way to find out what your application does when that dependency is down, which is usually less graceful than anyone expects. The same feature underpins chaos-engineering practice, with one important difference: here the blast radius is a field you control, so one drill never takes out the whole fleet the way one weak spot took out the Death Star.
