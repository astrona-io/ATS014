# Route Requests Within The Mesh

Astronaut, your first real mission is to steer signals. Right now a plain Kubernetes Service sends them blindly. A Service is a beacon: one call sign that a group of spaceships (pods) answers to. In your fleet, the `scout` beacon is answered by three ship classes, v1, v2 and v3. Every signal (request) lands on whichever ship `kube-proxy` happens to pick, like a message thrown into space for any ship to catch. You cannot say "send *my* signals to v2 while everyone else stays on v1", because a Service cannot read a signal. It only knows which ships answer its call sign.

Istio replaces that blind pick with a decision. The decision is made by the sidecar proxy, which can read the request. Think of the proxy as the communications officer on board each ship: every signal in or out goes through them. Two objects give it its orders, and the split between them is the thing to get right first:

> A `VirtualService` is the **flight plan**: it decides **where** a request goes. A `DestinationRule` is the **docking instructions**: it decides **what the named destinations mean**.

This module spends seven parts on these two objects because almost every later mission is this pair plus one extra field. Weighted shifting is a `VirtualService` route with numbers on it. Mirroring is the same rule with a `mirror` beside it. Timeouts, retries and fault injection are fields on the same `http` rule. Connection pools, load balancing and outlier detection are fields on the same `DestinationRule`. Learn the two objects well here, and most of the domain stops being new ideas and becomes new field names.

## Learning objectives

After this module you can:

- Explain the split of work between `VirtualService` and `DestinationRule`, and name which one creates subsets and which one uses them.
- Define subsets over pod labels, and predict what happens when a subset's labels match no pod.
- Send all traffic of a service to one subset, and switch it to another without touching the pods.
- Write `match` rules on `headers`, `uri`, `queryParams` and `method`, choosing correctly between `exact`, `prefix` and `regex`.
- State whether two match conditions are combined with AND or OR from their position in the YAML.
- Predict which `http` rule wins for a given request, and place a catch-all route correctly.
- Fill in a short host name to the namespace Istio will actually use.
- Use `redirect`, `rewrite`, `headers` and `corsPolicy` on a matched rule, and say which of them ends the request.
- Explain how a Service port's name or `appProtocol` decides the protocol, and diagnose a port declared as the wrong one.
- Tell `404 NR`, `503 NC` and `503 UH` apart from the access log, and say what each one means you should fix.

## Before you start

Every mission starts with a pre-flight check, astronaut. Before you write your first routing rule, make sure you have the knowledge this module expects, know what is waiting in your playground, and have one small helper ready in your terminal. It takes five minutes, and it saves you from chasing problems that have nothing to do with routing.

### What you should already know

- **How the mesh works.** A proxy (the communications officer) sits beside every pod, and `istiod` (mission control) sends it orders. You can read those orders with `istioctl proxy-config`.
- **Kubernetes basics.** Namespaces, Deployments, Services, pod labels and `kubectl exec`.

### What is in your playground

Your playground is a small training solar system: one `kind` cluster with **Istio 1.30.5** already installed. Everything you need is on one planet, the namespace **`starfleet`**.

The fleet on that planet is **the Starfleet**. It is the Bookinfo sample app that the official Istio docs use, with space names instead of the original ones. Here is the role each ship plays:

| Ship | Its role in the fleet |
| --- | --- |
| `bridge` | The **flagship**. It is the page astronauts see, and it sends signals to the other ships to build it |
| `cargo` | The **supply ship**. It answers with facts about an item |
| `scout` v1, v2, v3 | Three **ship classes** of the same scout. They answer the same call sign, but each one reports back differently: v1 with no stars, v2 with black stars, v3 with red stars. Yes, real stars |
| `navcom` | The **navigation computer**. The v2 and v3 scouts ask it for the star rating |
| `shuttle` | **Your shuttle**. You send every test signal from here, with the `curl` command |
| `probe` v1, v2 | An **echo probe**. It sends back exactly what it receives, so you can see what a signal looked like on arrival. The rewriting and non-HTTP parts use it |

Every pod shows `2/2`: the app plus its communications officer (the `istio-proxy` sidecar). There is **no** `VirtualService` and **no** `DestinationRule` yet. Writing them is your mission in this module.

One thing keeps its old name: the web paths built into the ships. A signal to the scout goes to `http://scout:9080/reviews/0`, and the bridge page lives at `/productpage`. The names of the ships changed, the paths inside them did not.

You can also watch the flagship from your browser at `http://127.0.0.1:9080/productpage`. Log in as your fellow astronaut `jason` (any password works). From then on, every signal the flagship sends to `scout` carries the label `end-user: jason`, and you will soon steer exactly those signals.

Launch your playground now, and keep it running next to you while you read the parts:

<!-- astrona:playground -->

### One helper to paste first

Paste this into each new terminal before you start. It sends 10 signals to `scout` and counts which version answered:

```sh
count_versions() { for i in $(seq 1 10); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s "$@" | grep -o 'scout-v[0-9]' || echo none
done | sort | uniq -c; }
SCOUT=http://scout:9080/reviews
```

Use it like this: `count_versions $SCOUT/0`. Any `curl` options you add, such as `-H "end-user: jason"`, are passed on.

## Why this matters

`VirtualService` and `DestinationRule` are the base of almost everything else in Istio traffic management. Most later features are one more field on one of these two objects, so time spent here pays off on every mission after it.

This module also trains the one habit every Istio astronaut needs. An object that `kubectl get` shows you and a proxy that actually follows it are two different facts. When your rule seems to do nothing, do not guess: ask the communications officer what orders they really hold, with `istioctl proxy-config`.
