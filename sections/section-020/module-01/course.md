# Shift Traffic With Weighted Routing

<!-- astrona:playground -->
> [!NOTE]
> 🧪 **Hands-on playground for this module** — a clean, throwaway machine to explore on. No task, no grading. Folder: [`playground/`](https://github.com/astrona-io/ATS014/tree/main/sections/section-020/module-01/playground)
>
> ```sh
> astrona run --git ssh://git@github.com/astrona-io/ATS014.git -c sections/section-020/module-01/playground
> astrona destroy ats-014-playground-020-01
> ```

In section 010 you sent a request to `v2` because *that request* carried a header. That is routing by identity: the same request always lands in the same place. Releasing a new version is a different problem. You do not want a particular request in `v2`; you want *some percentage of all traffic* there, with the percentage under your control, so that if the new version misbehaves you can turn it back down before most users notice.

That is weighted routing, and it is the mechanism behind every canary release. The object is the `VirtualService` you already know. The change is one field.

> Weights split traffic across subsets of one host, and they must add up to 100.

What makes it worth three parts is not the field — it is everything around it. The split is statistical rather than scheduled, so measuring it wrong is easy. The patch that changes it replaces a list rather than editing it. And the single most reliable exam question on the topic is about the relationship between a weight and a replica count, which is that there is none.

## How this module is organised

1. **[Part 1 — Weighted Destinations](./course-01-weighted-destinations.md)** — several destinations in one route block, the 100-sum rule and what enforces it, and how a weight becomes a per-request decision inside Envoy.
2. **[Part 2 — Running A Rollout](./course-02-running-a-rollout.md)** — a canary as a sequence of applies, why rollback is the same operation, and how to measure a statistical split without fooling yourself.
3. **[Part 3 — Weight Versus Replicas, And Proof](./course-03-weight-versus-replicas-and-proof.md)** — where the weighted choice happens relative to endpoint load balancing, why scaling changes nothing, and reading `weightedClusters` out of a live proxy.

## Learning objectives

After this module you can:

- Write a `VirtualService` route with several weighted destinations, and place `weight` on the correct field.
- State the 100-sum rule and say what happens when it is broken, and when `weight` may be omitted.
- Explain how the proxy applies a weight — per request, independently — and what that means for sample size.
- Run a canary rollout as a sequence of weight changes and roll it back in one apply.
- Explain why a merge patch on `spec.http` must restate the whole route block.
- Explain why traffic share and replica count are independent, and predict the split when they disagree.
- Read `weightedClusters` from `istioctl proxy-config routes` and match each entry to your YAML.

## Before you start

You need section 010's two objects in your head: `DestinationRule` defines subsets, `VirtualService` routes to them. Weighted routing adds nothing conceptually new to that pair — it only puts numbers on the destinations — so if subsets are still shaky, re-read Module 1 Part 1 first.

The playground gives you a single-node `kind` cluster with **Istio 1.30.5 already installed** (the `demo` profile) and the namespace **`shifting-demo`**, injected, containing `notification-service-v1`, `notification-service-v2`, a `notification-service` Service in front of both, and a `tester` client pod. `v1` answers `["EMAIL"]` and `v2` answers `["EMAIL","SMS"]`, which is what lets you count a split from the responses alone. No `VirtualService` or `DestinationRule` exists yet.

## Where this fits

Weighted routing is the first of several fields that hang off the same `http` rule. Mirroring, the next module, is a sibling field on the same rule that sends a *copy* somewhere — a different answer to the same "how do I test a new version" question. Timeouts, retries and fault injection in sections 040 and 050 are further fields on that rule. The shape you learn here is the shape they all share.
