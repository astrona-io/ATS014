# Configuring Routing Within A Service Mesh

Welcome to your first steering mission, astronaut. In this section you learn to decide where every signal in the fleet flies.

A Kubernetes Service is a beacon: one call sign that a whole group of ships (pods) answers to. It shares the signals out between the ships, but it cannot read a signal, and it cannot be told that some signals matter more than others. Istio's answer is a communications officer (a proxy) on every ship, plus two objects that tell that officer what to do with the signals it sees. A `VirtualService` is the flight plan. A `DestinationRule` is the docking instructions.

This section covers both ends of that idea. First, it follows the signal’s journey: how a rule matches, which destination it selects, what else a matched rule can do to it, and how to prove the rule reached the proxy.

Then it looks at the opposite direction. It asks how much of the star chart each ship should carry, and how to reduce the full service registry to only the hosts a workload actually needs to communicate with.

Finally, it covers timing: the order in which these objects should be applied and removed so no signal ever points to something that does not exist yet — “make before break” — along with the defaults Istio uses when you leave the configuration unspecified.

---

## What You Will Master

- The division of labour between `VirtualService` (where a request goes) and `DestinationRule` (what the named destinations mean).
- How `istiod` turns the registry into Envoy clusters, and how to read the `outbound|port|subset|host` cluster name.
- Defining subsets over pod labels, and why a subset whose labels match nothing is legal configuration and a later 503.
- Matching on `headers`, `uri`, `queryParams` and `method`, with the `exact` / `prefix` / `regex` forms and RE2's limits.
- The AND/OR rule: conditions inside one `-` entry are ANDed, separate entries are ORed.
- Top-down first-match evaluation, and why a default route placed first silently kills everything below it.
- Short host names resolving relative to the object's own namespace — and the failures that causes.
- The two failure signatures: wrong-destination-no-error versus bare 503, and which half of the module each points at.
- What a sidecar is programmed with by default, how xDS delivers it, and why the cost scales with the cluster.
- Narrowing with `Sidecar` and `egress[].hosts` in `<namespace>/<host>` form, and why `istio-system/*` is boilerplate.
- `Sidecar` precedence: selective beats namespace default beats root namespace, and each replaces rather than merges.
- Why `Sidecar` is a configuration control rather than a security boundary, and what to combine it with.
- Using `redirect`, `rewrite`, `headers` and `corsPolicy` on a matched rule, and which of them ends the request.
- How a Service port's name or `appProtocol` decides the protocol — and how a port declared as `tcp` silently turns off every HTTP feature.
- What a `tcp` or `tls` rule can match on when there is no request to read, and what per-connection balancing costs you.
- Reading a proxy's live configuration with `istioctl proxy-config routes`, `cluster`, `endpoints` and `listener`.
- The order to apply and remove `ServiceEntry`, `DestinationRule`, `Gateway` and `VirtualService` ("make before break"), and Istio's defaults for timeouts, retries, load balancing and outbound traffic.

---

<!-- astrona:playground:environment-explain -->
