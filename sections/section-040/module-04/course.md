# Locality Load Balancing And Failover

<!-- astrona:playground -->
> [!NOTE]
> 🧪 **Hands-on playground for this module** — a clean, throwaway machine to explore on. No task, no grading. Folder: `playground/`
>
> ```sh
> astrona run --git ssh://git@github.com/astrona-io/ATS014.git -c sections/section-040/module-04/playground
> astrona destroy ats-014-playground-040-04
> ```

Astronaut, picture your fleet spread over three orbits. A signal to a ship in your own orbit is quick. A signal to a ship in another orbit takes longer, and costs fuel. A cluster spanning three availability zones has the same cost, and it appears in no Istio object: cross-zone traffic is slower than same-zone traffic, and in most clouds you are billed for it. Round robin across all endpoints, indifferent to where they are, maximises both.

Locality load balancing makes the proxy prefer nearby endpoints. Locality *failover* is the other half: when nearby endpoints stop working, spill over to a further-away locality rather than failing, like switching to a ship orbiting another planet when the nearest one goes dark.

Two facts carry the module, and the second is the most examinable thing in section 040:

> Locality preference is **on by default**. Locality **failover** only works if something marks endpoints unhealthy — and that something is `outlierDetection`.

## How this module is organised

1. **[Where Locality Comes From](./course-01-where-locality-comes-from.md)** — the node labels Istio reads, the `region/zone/subzone` hierarchy, the `istio-locality` pod override, and how to confirm an endpoint actually has a locality before configuring anything.
2. **[Preference, `distribute` And `failover`](./course-02-preference-distribute-and-failover.md)** — what Istio already does without configuration, and the two mutually exclusive ways to change it.
3. **[The Health Dependency And Scope](./course-03-the-health-dependency-and-scope.md)** — why failover is dead without outlier detection, mesh-wide versus per-host configuration, and what this playground can and cannot demonstrate.

## Learning objectives

After this module you can:

- Name the labels Istio derives an endpoint's locality from, and state the `region/zone/subzone` hierarchy.
- Use the `istio-locality` pod label and say when it is needed.
- Confirm from a live proxy that endpoints carry a locality, and recognise the empty-locality failure before it wastes your time.
- Describe Istio's default locality behaviour with no `localityLbSetting` at all.
- Configure `distribute` for explicit cross-locality weights and `failover` for region-level fallback, and say why they are mutually exclusive.
- Explain why a `localityLbSetting` without `outlierDetection` never fails over.
- Choose between mesh-wide `meshConfig.localityLbSetting` and a per-host `DestinationRule`.

## Before you start

This module assumes [section 000](../../section-000/module-01/course.md): a proxy (the communications officer) beside every pod, `istiod` (mission control) programming it over xDS, and `istioctl proxy-config` as the way to see what a proxy actually holds rather than what you hoped it holds.

You need `outlierDetection` from module 3 — this module is built directly on top of it — and `DestinationRule.trafficPolicy` generally.

The playground gives you a training solar system: a single-node `kind` cluster with **Istio 1.30.5 already installed** (the `demo` profile) and the namespace **`locality-demo`**, injected, containing `httpbin-zone-a` and `httpbin-zone-b` (one replica each) behind one `httpbin` Service on port 8000, plus a `tester` client.

**One adaptation matters.** Locality normally comes from the **node** a pod runs on, which needs a multi-node cluster with different zone labels. This playground has one node, so the two Deployments declare their locality directly with the **`istio-locality` pod label** (`local.zone-a` and `local.zone-b`) — a documented Istio override for exactly this situation. Everything about `localityLbSetting` behaves identically; what you cannot observe here is real cross-zone latency, because both pods are on the same machine. The matching lab under `domains/` uses node affinity and expects a real multi-node cluster.

## Where this fits

This is the last of section 040's resilience features and the one that depends on the others. It consumes module 3's notion of an unhealthy endpoint, and it composes with module 1's retries through `retryRemoteLocalities`, which allows a retry to cross a locality boundary that the initial attempt would not have. On the exam, the locality question is usually really an outlier-detection question in disguise.
