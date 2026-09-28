# Route Requests By Header, URI And Query Parameter

<!-- astrona:playground -->
> [!NOTE]
> 🧪 **Hands-on playground for this module** — a clean, throwaway machine to explore on. No task, no grading. Folder: [`playground/`](https://github.com/astrona-io/ATS014/tree/main/sections/section-010/module-01/playground)
>
> ```sh
> astrona run --git ssh://git@github.com/astrona-io/ATS014.git -c sections/section-010/module-01/playground
> astrona destroy ats-014-playground-010-01
> ```

A plain Kubernetes Service is a coin toss. Two versions of `notification-service` are running, both match the Service selector, and every request lands on whichever pod kube-proxy happens to pick. You cannot say "send *my* requests to v2 while everyone else stays on v1", because a Service has no idea what a request looks like. It only knows about pods.

Istio replaces that coin toss with a decision, made by a proxy that can read the request. Two objects carry it, and the split between them is the thing to get right first:

> A `VirtualService` decides **where** a request goes; a `DestinationRule` decides **what the named destinations mean**.

What makes this worth three parts is that almost every later module is this pair with one extra field. Weighted shifting is a `VirtualService` route with numbers on it. Mirroring is the same rule with a `mirror` beside it. Timeouts, retries and fault injection are fields on the same `http` entry. Connection pools, load balancer policy and outlier detection are fields on the same `DestinationRule`. Learn the two objects properly here and most of the domain stops being new concepts and starts being new field names.

## How this module is organised

1. **[Subsets And The Destination Vocabulary](./course-01-subsets-and-destination-vocabulary.md)** — what a `DestinationRule` actually creates, how a subset name becomes an Envoy cluster, and why applying one on its own moves no traffic at all.
2. **[Matching A Request](./course-02-matching-a-request.md)** — the `match` block in detail: the four match types, the three string forms, and the AND/OR rule that decides whether two conditions must both hold.
3. **[Evaluation Order, Name Resolution And Proof](./course-03-evaluation-order-and-proof.md)** — top-down first-match evaluation, why the default route must be last, how short host names resolve, and how to prove the proxy received what you wrote.

## Learning objectives

After this module you can:

- Explain the division of labour between `VirtualService` and `DestinationRule`, and name which one creates subsets and which one consumes them.
- Define subsets over pod labels and predict what happens when a subset's labels match no pod.
- Read an Envoy cluster name and identify the direction, port, subset and host encoded in it.
- Write `match` rules on `headers`, `uri`, `queryParams` and `method`, choosing correctly between `exact`, `prefix` and `regex`.
- State whether two match conditions are ANDed or ORed from their position in the YAML.
- Predict which `http` rule wins for a given request, and place a default route correctly.
- Resolve a short host name to the namespace Istio will actually look in.
- Diagnose the two classic failures — a default route placed first, and a subset no `DestinationRule` defines — from their symptoms.
- Prove a routing change reached the sidecar with `istioctl proxy-config routes`.

## Before you start

You should be comfortable with `kubectl` against a cluster you have admin rights on: namespaces, Deployments, Services, pod labels, and `kubectl exec`. No prior Istio experience is assumed — every Istio object is introduced before it is used.

The playground gives you a single-node `kind` cluster with **Istio 1.30.5 already installed** (the `demo` profile), `istioctl` on your PATH, and the namespace **`routing-demo`** populated:

- `notification-service-v1` and `notification-service-v2` — one Deployment each, both labelled `app: notification-service`, distinguished by a `version` label. `v1` answers `["EMAIL"]` and `v2` answers `["EMAIL","SMS"]`, which is how you tell from a response body which one served you.
- `notification-service` — one Service in front of both.
- `tester` — a client pod with `curl`.

Every pod there already has an `istio-proxy` sidecar. What the playground deliberately does **not** create is any `VirtualService` or `DestinationRule` — writing those is the subject of the module. All commands run in your normal shell, with `kubectl` already pointed at the cluster.

## Where this fits

This is the first of the `networking.istio.io` objects because the rest are built from it. It is also the first place the course's standing diagnostic habit appears: an object existing in `kubectl` and a proxy acting on it are two different facts, and when they disagree the answer is always in `istioctl proxy-config`. Part 3 makes that habit explicit; every later module assumes it.
