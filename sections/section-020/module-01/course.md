# Shift Traffic With Weighted Routing

<!-- astrona:playground -->
> [!NOTE]
> 🧪 **Hands-on playground for this module** — a clean, throwaway machine to explore on. No task, no grading. Folder: `playground/`
>
> ```sh
> astrona run --git ssh://git@github.com/astrona-io/ATS014.git -c sections/section-020/module-01/playground
> astrona destroy ats-014-playground-020-01
> ```

Astronaut, your mission in this module is a safe launch: put a new ship class into service without risking the whole fleet. In section 010 you sent a request to a version because *that request* carried a header. That is routing by identity: the same request always lands in the same place. Releasing a new version is a different problem. You do not want one particular request on the new version. You want *a share of all traffic* there, with the share under your control, so that if the new version misbehaves you can turn it back down before most users notice.

That is weighted routing, and it is how every canary release works in Istio. Think of it as sending a small share of signals to the new ship class before the whole fleet switches over. The object is the `VirtualService` you already know, the flight plan for a service. The change is one field.

> Weights split traffic across subsets of one host. Write them so they add up to 100.

The field is small. What makes it worth three parts is everything around it. The split is random per request, so it is easy to measure wrong. A patch that changes it replaces a whole list instead of editing it. And the exam question that comes up most is about weight and replica count, which have nothing to do with each other.

## How this module is organised

1. **[Weighted Destinations](./course-01-weighted-destinations.md)** — several destinations in one route, what Istio does with weights that do not add up to 100, three-way splits and `weight: 0`, and how a weight becomes a per-request decision inside Envoy.
2. **[Running A Rollout](./course-02-running-a-rollout.md)** — a canary as a series of applies, why rollback is the same move, testers pinned above a split, and how to measure a random split without fooling yourself.
3. **[Weight Versus Replicas, And Proof](./course-03-weight-versus-replicas-and-proof.md)** — where the weighted choice happens compared with load balancing, why scaling changes nothing, and reading `weightedClusters` out of a live sidecar.

## Learning objectives

After this module you can:

- Write a `VirtualService` route with several weighted destinations, and place `weight` on the correct field.
- Write weights that add up to 100, predict the split when they do not, and say when `weight` may be left out.
- Explain how the proxy applies a weight — per request, independently — and what that means for sample size.
- Run a canary rollout as a series of weight changes and roll it back in one apply.
- Combine a header match with a weighted split, and predict which requests the weights apply to.
- Explain why a merge patch on `spec.http` must restate the whole route block.
- Explain why traffic share and replica count are independent, and predict the split when they disagree.
- Read `weightedClusters` from `istioctl proxy-config routes` and match each entry to your YAML.

## Before you start

This module assumes [section 000](../../section-000/module-01/course.md): a sidecar beside every pod, `istiod` programming it over xDS, and `istioctl proxy-config` as the way to see what a sidecar really holds, not what you hoped it holds.

You need section 010's two objects in your head. A `DestinationRule` defines subsets, and a `VirtualService` routes to them. Weighted routing adds nothing new to that pair. It only puts numbers on the destinations. If subsets still feel shaky, re-read Module 1 Part 1 first.

The playground gives you a single-node `kind` cluster with **Istio 1.30.5**, installed with Helm (`istio-base` and `istiod`, no gateways). Namespace **`starfleet`** (your planet) is injected and holds the Starfleet, the Istio docs' Bookinfo sample with space names: `bridge` (the flagship page), `cargo` (the supply ship), `navcom` (the navigation computer) and `scout` in three versions. `scout` v1 shows no stars, v2 black stars and v3 red stars — three ship classes of the same model — and each answer names the spaceship (pod) that sent it. That is how you count a split. The scout still answers on its original path, `/reviews/0`, because the path is built into the app. There is also `shuttle`, the client pod you send every test signal from, and `probe`, an echo test service. The `scout` `DestinationRule` with subsets `v1`, `v2` and `v3` is already applied. No `VirtualService` exists yet. The playground [overview](./playground/docs/overview.md) has the `count_versions` helper every "Try it" uses.

The graded lab for this module runs in its own environment, on the `notification-service` app. The ideas are the same; only the names differ.

## Where this fits

Weighted routing is the first of several fields that hang off the same `http` rule. Mirroring, the next module, is a sibling field on the same rule that sends a *copy* somewhere — a different answer to the same "how do I test a new version" question. Timeouts, retries and fault injection in sections 040 and 050 are further fields on that rule. The shape you learn here is the shape they all share.
