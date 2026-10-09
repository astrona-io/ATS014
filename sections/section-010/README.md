# Configuring Routing Within A Service Mesh

In this section you learn to decide where every request in the mesh goes.

A Kubernetes Service gives a group of pods one name and one address. It spreads requests across those pods, but it cannot read a request, and it cannot treat some requests differently from others. Istio adds a sidecar proxy to every pod, plus two objects that tell the proxy what to do with each request. A `VirtualService` sets how requests to a host are routed. A `DestinationRule` defines the destinations a route can pick, such as subsets of pods by version.

The section starts with the path of one request: how a rule matches, which destination it selects, what else a matched rule can change, and how to prove the rule reached the proxy.

Then it looks at the proxy's configuration size. By default every sidecar proxy gets configuration for every host in the service registry. The `Sidecar` resource cuts that down to only the hosts a workload needs.

Finally, it covers order: how to apply and remove these objects so no route ever points at something that does not exist yet ("make before break"), and the defaults Istio uses when you leave a setting out.

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
- What a sidecar is programmed with by default, how xDS (the discovery services `istiod` uses to send proxy settings) delivers it, and why the cost scales with the cluster.
- Narrowing with `Sidecar` and `egress[].hosts` in `<namespace>/<host>` form, and why `istio-system/*` is boilerplate.
- `Sidecar` precedence: selective beats namespace default beats root namespace, and each replaces rather than merges.
- Why `Sidecar` is a configuration control rather than a security boundary, and what to combine it with.
- Using `redirect`, `rewrite`, `headers` and `corsPolicy` on a matched rule, and which of them ends the request.
- How a Service port's name or `appProtocol` decides the protocol — and how a port declared as `tcp` silently turns off every HTTP feature.
- What a `tcp` or `tls` rule can match on when there is no request to read, and what per-connection balancing costs you.
- Reading a proxy's live configuration with `istioctl proxy-config routes`, `cluster`, `endpoints` and `listener`.
- The order to apply and remove `ServiceEntry`, `DestinationRule`, `Gateway` and `VirtualService` ("make before break"), and Istio's defaults for timeouts, retries, load balancing and outbound traffic.

---

## Modules In This Section

Work through the modules in this order. Each part teaches one idea. A mission (a graded lab) comes right after the part it practises, and the last page of each module is a wrap-up. The capstone at the end uses everything in the section at once.

### Route Requests Within The Mesh

9 parts and 5 missions:

1. Where Signals Go Today
2. Name The Ship Classes
   - Mission: Fix The Docking Instructions Lab
3. Write A Flight Plan
4. Match Exactly What You Mean
5. Put Your Rules In Order
   - Mission: Route Requests By Header, URI And Query Parameter Lab
6. Put The Flight Plan On The Right Planet
7. Read The Flight Log And The Proxy's Orders
   - Mission: Find Out Why The Flight Plan Does Nothing Lab
8. Rewriting, Redirecting And Headers
   - Mission: Reshape A Request Lab
9. Routing Non-HTTP Traffic
   - Mission: Bring HTTP Routing Back Lab
10. Wrap-Up: Mission Debrief

### Scope Proxy Configuration With The Sidecar Resource

4 parts and 2 missions:

1. Every Ship Carries The Whole Star Chart
2. Give A Ship A Smaller Star Chart
   - Mission: Scope Proxy Configuration With The Sidecar Resource Lab
3. Which Star Chart A Ship Uses
   - Mission: Fix One Ship's Star Chart Lab
4. A Star Chart Is Not A Shield
5. Wrap-Up: Mission Debrief

### Apply And Remove Traffic Rules Safely

2 parts and 1 mission:

1. The Order To Apply And Remove Rules
   - Mission: Retire A Ship Class Safely Lab
2. One Object Per Host, And The Defaults
3. Wrap-Up: Mission Debrief

### Capstone

The section ends with a capstone lab that uses everything in it: **Route And Scope A Storefront Capstone Lab**.

---

<!-- astrona:playground:environment-explain -->
