# Mirror Live Traffic To A Shadow Service

<!-- astrona:playground -->
> [!NOTE]
> 🧪 **Hands-on playground for this module** — a clean, throwaway machine to explore on. No task, no grading. Folder: `playground/`
>
> ```sh
> astrona run --git ssh://git@github.com/astrona-io/ATS014.git -c sections/section-020/module-02/playground
> astrona destroy ats-014-playground-020-02
> ```

Astronaut, this module is about testing a new ship without letting it talk to anyone. Weighted shifting has one uncomfortable side. To find out how a new version behaves under real traffic, you have to give it real users. Even at 1%, those are somebody's requests. If v2 is broken, they get the broken answer.

**Mirroring** (also called shadowing) removes that trade-off. Think of it as sending a copy of each signal to a test ship: the proven ship still answers, and the test ship's replies are ignored. In mesh terms, the sidecar sends the request to the old version as usual, and *also* sends a copy to the new one. The caller's answer comes from the old version, every time. The copy's answer is thrown away, and so is its delay. The new version sees real traffic (the real request shapes, the real volume, the awkward payloads nobody writes tests for) while users never see it.

The cost is that a copy of a request is still a request. If the shadow writes to a database, it writes.

## How this module is organised

1. **[Mirror As A Sibling Of Route](./course-01-mirror-as-a-sibling-of-route.md)** — "answered" versus "received", where the field sits, why the mirrored answer is thrown away, and a shadow that fails while the caller stays fine.
2. **[Identifying And Sampling Shadow Traffic](./course-02-identifying-and-sampling-shadow-traffic.md)** — proving a mirror works from the receiving pod's logs, what happened to the old `-shadow` authority suffix, and lowering the copy rate with `mirrorPercentage`.
3. **[Consequences, Verification And Limits](./course-03-consequences-verification-and-limits.md)** — the side effects that make mirroring unsafe, a mirror combined with a weighted split, and finding `requestMirrorPolicies` in a live sidecar.

## Learning objectives

After this module you can:

- Add a `mirror` destination to an HTTP route and say which response the caller receives.
- Explain why a mirror is not part of the `route` weighted split, and predict how many requests each version receives when a split and a mirror are combined.
- Control the copied share with `mirrorPercentage`, and state the default when it is omitted.
- Recognise mirrored traffic on the receiving side from the shadow proxy's access log, and explain why the old `-shadow` authority suffix is not something to check for on 1.30.
- Diagnose a mirror that is silently doing nothing.
- Judge when mirroring is safe, and name the side effects that make it unsafe.
- Verify a mirror from `istioctl proxy-config routes`.

## Before you start

This module assumes [section 000](../../section-000/module-01/course.md): a sidecar beside every pod, `istiod` programming it over xDS, and `istioctl proxy-config` as the way to see what a sidecar really holds, not what you hoped it holds.

You need `VirtualService` and `DestinationRule` subsets from section 010. It helps to have done weighted shifting first, because mirroring is easiest to understand as the thing weighted shifting is not.

The playground gives you a single-node `kind` cluster with **Istio 1.30.5**, installed with Helm (`istio-base` and `istiod`, no gateways), and access logs on for the whole mesh. On the planet **`starfleet`** (an injected namespace) you find **`probe`**, the echo probe that sends back what it receives, on port `8000` in two versions, `probe-v1` and `probe-v2`, behind one Service. Next to it is **`shuttle`**, your test client: you send every test signal from it. `/hostname` returns the name of the pod that answered. The official mirroring task uses the same echo service (there it is called `httpbin`), so you can follow both side by side. No `DestinationRule` or `VirtualService` exists yet. The playground [overview](./playground/docs/overview.md) has the `mark_start`, `count_received` and `send_requests` helpers every "Try it" uses.

The graded lab for this module runs in its own environment, on the `notification-service` app. The ideas are the same; only the names differ.

## Where this fits

Mirroring and weighted shifting answer the same question — "is the new version safe?" — from opposite ends, and choosing between them is a real decision rather than a preference. Weights expose real users to real answers and give you the new version's *responses*. Mirroring exposes nobody and gives you the new version's *behaviour under load*, with no way to compare what it would have returned. In practice they are used in sequence: mirror first to find crashes and performance problems, then shift weight once the shadow has been quiet for a while.
