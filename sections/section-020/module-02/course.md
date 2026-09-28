# Mirror Live Traffic To A Shadow Service

<!-- astrona:playground -->
> [!NOTE]
> 🧪 **Hands-on playground for this module** — a clean, throwaway machine to explore on. No task, no grading. Folder: [`playground/`](https://github.com/astrona-io/ATS014/tree/main/sections/section-020/module-02/playground)
>
> ```sh
> astrona run --git ssh://git@github.com/astrona-io/ATS014.git -c sections/section-020/module-02/playground
> astrona destroy ats-014-playground-020-02
> ```

Weighted shifting has one uncomfortable property: to find out how a new version behaves under real traffic, you have to give it real users. Even at 1% those are somebody's requests, and if `v2` is broken they get the broken answer.

Mirroring removes that trade. The proxy sends the request to the old version as usual and *also* sends a copy to the new one. The caller's response comes from the old version, every time. The copy's response is thrown away, and so is its latency. The new version sees production traffic — the real request shapes, the real volume, the awkward payloads nobody writes tests for — while remaining invisible to users.

The cost is that a copy of a request is still a request. If the shadow writes to a database, it writes.

## How this module is organised

1. **[Mirror As A Sibling Of Route](./course-01-mirror-as-a-sibling-of-route.md)** — where the field sits, why the mirrored response is discarded, and why a mirror is never part of a weighted split.
2. **[Identifying And Sampling Shadow Traffic](./course-02-identifying-and-sampling-shadow-traffic.md)** — proving a mirror works from the receiving proxy's access log, what happened to the old `-shadow` authority suffix, and cutting the copy rate with `mirrorPercentage`.
3. **[Consequences, Verification And Limits](./course-03-consequences-verification-and-limits.md)** — the side effects that make mirroring unsafe, finding `requestMirrorPolicies` in a live proxy, and the module's pitfalls.

## Learning objectives

After this module you can:

- Add a `mirror` destination to an HTTP route and say which response the caller receives.
- Explain why a mirror is not part of the `route` weighted split, and what that means for total request volume.
- Control the copied share with `mirrorPercentage`, and state the default when it is omitted.
- Recognise mirrored traffic on the receiving side from the shadow proxy's access log, and explain why the old `-shadow` authority suffix is not something to check for on 1.30.
- Diagnose a mirror that is silently doing nothing.
- Judge when mirroring is safe, and name the side effects that make it unsafe.
- Verify a mirror from `istioctl proxy-config routes`.

## Before you start

You need `VirtualService` and `DestinationRule` subsets from section 010, and it helps to have done weighted shifting first — mirroring is best understood as the thing weighted shifting is not.

The playground gives you a single-node `kind` cluster with **Istio 1.30.5 already installed** (the `demo` profile) and the namespace **`mirror-demo`**, injected, holding `notification-service-v1` and `notification-service-v2` behind one `notification-service` Service, plus a `tester` client pod. `v1` answers `["EMAIL"]`, `v2` answers `["EMAIL","SMS"]`. No Istio traffic configuration exists yet.

## Where this fits

Mirroring and weighted shifting answer the same question — "is the new version safe?" — from opposite ends, and choosing between them is a real decision rather than a preference. Weights expose real users to real answers and give you the new version's *responses*. Mirroring exposes nobody and gives you the new version's *behaviour under load*, with no way to compare what it would have returned. In practice they are used in sequence: mirror first to find crashes and performance problems, then shift weight once the shadow has been quiet for a while.
