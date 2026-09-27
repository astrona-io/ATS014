# Outlier Detection And Endpoint Ejection

<!-- astrona:playground -->
> [!NOTE]
> 🧪 **Hands-on playground for this module** — a clean, throwaway machine to explore on. No task, no grading. Folder: [`playground/`](https://github.com/astrona-io/ATS014/tree/main/sections/section-040/module-03/playground)
>
> ```sh
> astrona run --git ssh://git@github.com/astrona-io/ATS014.git -c sections/section-040/module-03/playground
> astrona destroy ats-014-playground-040-03
> ```

Kubernetes already has a way to remove a broken pod from a Service: the readiness probe. It works when the pod knows it is broken. It does nothing about the pod that answers its probe cheerfully while returning 503 to every real request — a bad config, a dead dependency, a corrupted cache, a connection pool it has exhausted internally. That pod stays in the Service, and a share of your traffic keeps failing.

Outlier detection is the mesh's answer, and it works differently from anything else in this section: there is no probe at all. The client proxy watches the responses it is **already receiving**, notices that one endpoint keeps failing, and stops sending to it.

## How this module is organised

1. **[Part 1 — Passive Health Checking](./course-01-passive-health-checking.md)** — what "passive" means, the fields that define an outlier, and how this differs from a readiness probe in kind rather than degree.
2. **[Part 2 — Ejection Mechanics And Limits](./course-02-ejection-mechanics-and-limits.md)** — the analysis interval, how long an ejection lasts and why repeat offenders are ejected for longer, and the two safety limits that stop the mesh ejecting everything.
3. **[Part 3 — Local, Temporary, And Verified](./course-03-local-temporary-and-verified.md)** — why every proxy reaches its own verdict, what Kubernetes thinks meanwhile, the counters that prove an ejection, and how this becomes the foundation for locality failover.

## Learning objectives

After this module you can:

- Explain what passive health checking is and how it differs from a readiness probe.
- Configure `trafficPolicy.outlierDetection` with `consecutive5xxErrors`, `interval`, `baseEjectionTime` and `maxEjectionPercent`.
- Explain why `maxEjectionPercent` at its default prevents any ejection on a small service.
- Predict how long an endpoint stays ejected, including after repeated ejections.
- Explain why enough traffic is needed before an ejection can happen at all.
- Show an active ejection from a proxy's statistics and endpoint view, and explain why `kubectl get endpoints` disagrees.
- State why locality failover depends on this module.

## Before you start

You need `DestinationRule` and `trafficPolicy` from section 030. This module adds a key beside `connectionPool` — Istio's documentation groups the two together as "circuit breaking", and they are frequently configured together.

The playground gives you a single-node `kind` cluster with **Istio 1.30.5 already installed** (the `demo` profile) and the namespace **`outlier-demo`**, injected, containing:

- `httpbin-good` — one replica that answers normally.
- `httpbin-bad` — one replica of nginx configured to return **503 to everything**. It is perfectly healthy as far as Kubernetes is concerned: its readiness probe passes and it stays in the Service. That is the whole point.
- `httpbin` — one Service on port 8000 in front of **both**, so the Service has two endpoints and one of them is poison.
- `tester` — a client pod with `curl`.

No `DestinationRule` exists yet.

## Where this fits

This module supplies the notion of an "unhealthy endpoint" that the next one depends on. Locality failover has no health checker of its own; it re-uses this one, which is why a locality configuration without `outlierDetection` never fails over. It also interacts with module 1: retries can hide the failures from the caller while the proxy quietly collects the evidence it needs to eject, which is a genuinely good combination.
