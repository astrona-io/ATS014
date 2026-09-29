# Route Requests Within The Mesh

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

What makes this worth five parts is that almost every later module is this pair with one extra field. Weighted shifting is a `VirtualService` route with numbers on it. Mirroring is the same rule with a `mirror` beside it. Timeouts, retries and fault injection are fields on the same `http` entry. Connection pools, load balancer policy and outlier detection are fields on the same `DestinationRule`. Learn the two objects properly here and most of the domain stops being new concepts and starts being new field names.

## How this module is organised

1. **[Subsets And The Destination Vocabulary](./course-01-subsets-and-destination-vocabulary.md)** — what a `DestinationRule` actually creates, how a subset name becomes an Envoy cluster, and why applying one on its own moves no traffic at all.
2. **[Matching A Request](./course-02-matching-a-request.md)** — the `VirtualService` object, then the `match` block in detail: the four match types, the three string forms, and the AND/OR rule that decides whether two conditions must both hold.
3. **[Evaluation Order, Name Resolution And Proof](./course-03-evaluation-order-and-proof.md)** — top-down first-match evaluation, why the default route must be last, how short host names resolve, and how to prove the proxy received what you wrote.
4. **[Rewriting, Redirecting And Headers](./course-04-rewriting-redirecting-and-headers.md)** — the other things a matched rule can do: answer with a redirect, rewrite the path, add or strip headers, and handle CORS preflights.
5. **[Routing Non-HTTP Traffic](./course-05-routing-non-http-traffic.md)** — how a Service port's *name* decides whether you get HTTP routing at all, and what `tcp` and `tls` rules can match on when there is no request to read.

Parts 1 to 3 are the module's graded material and the lab is built from them. Parts 4 and 5 cover fields on the same objects that the exam expects you to recognise, and one silent failure — a misnamed Service port — that is worth meeting deliberately rather than in production.

## Learning objectives

After this module you can:

- Explain the division of labour between `VirtualService` and `DestinationRule`, and name which one creates subsets and which one consumes them.
- Define subsets over pod labels, and predict what happens when a subset's labels match no pod.
- Write `match` rules on `headers`, `uri`, `queryParams` and `method`, choosing correctly between `exact`, `prefix` and `regex`.
- State whether two match conditions are ANDed or ORed from their position in the YAML.
- Predict which `http` rule wins for a given request, and place a default route correctly.
- Resolve a short host name to the namespace Istio will actually look in.
- Use `redirect`, `rewrite`, `headers` and `corsPolicy` on a matched rule, and say which of them ends the request.
- Explain how a Service port's name or `appProtocol` decides the protocol, and diagnose the silent fallback to plain TCP.
- Diagnose the classic failures — a default route placed first, a subset no `DestinationRule` defines, and an object in the wrong namespace — from their symptoms.

## Before you start

This module assumes [section 000](../../section-000/module-01/course.md): that a proxy sits beside every pod, that `istiod` programs it over xDS, that an Envoy cluster is a named destination, and that `istioctl proxy-config` prints what a proxy currently holds. If any of that is new, read that module first — it is short, and everything here builds on it.

You should also be comfortable with `kubectl` against a cluster you have admin rights on: namespaces, Deployments, Services, pod labels, and `kubectl exec`.

The playground gives you a single-node `kind` cluster with **Istio 1.30.5 already installed** (the `demo` profile), `istioctl` on your PATH, and the namespace **`routing-demo`** populated:

- `notification-service-v1` and `notification-service-v2` — one Deployment each, both labelled `app: notification-service`, distinguished by a `version` label. `v1` answers `["EMAIL"]` and `v2` answers `["EMAIL","SMS"]`, which is how you tell from a response body which one served you.
- `notification-service` — one Service in front of both, on port `80` named `http`, targeting container port `8084`.
- `tester` — a client pod with `curl`.

Every pod there already has an `istio-proxy` sidecar. What the playground deliberately does **not** create is any `VirtualService` or `DestinationRule` — writing those is the subject of the module. All commands run in your normal shell, with `kubectl` already pointed at the cluster.

## Where this fits

This is the first of the `networking.istio.io` objects because the rest are built from it. It is also where the course's standing diagnostic habit gets its first real workout: an object existing in `kubectl` and a proxy acting on it are two different facts, and when they disagree the answer is in `istioctl proxy-config`. Section 000 introduced that habit; Part 3 makes it routine, and every later module assumes it.
