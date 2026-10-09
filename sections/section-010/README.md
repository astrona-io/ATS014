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

Work through the modules in this order. Each part teaches one idea. A graded lab comes right after the part it practises, and the last page of each module is a summary. The capstone lab at the end uses everything in the section at once.

### Route Requests Within The Mesh

12 parts and 5 labs:

1. See Where Requests Go Without Routing Rules
2. Define Subsets With A DestinationRule
   - Lab: Fix A DestinationRule Subset That Selects No Pods Lab
3. Route Requests With A VirtualService
4. Match Text With Exact, Prefix And Regex
5. Combine Match Conditions With AND Or OR
6. Read A Compiled Match In The Route Table
7. Order Routing Rules And Add A Catch-All
   - Lab: Route Requests By Header, URI And Query Parameter Lab
8. Resolve Short Host Names To The Right Namespace
9. Debug Routing With The Access Log And proxy-config
   - Lab: Fix A VirtualService That Does Not Apply Lab
10. Redirect And Rewrite Requests
11. Change Headers And Answer CORS Preflight Requests
   - Lab: Redirect, Rewrite And Change Headers Of A Request Lab
12. Protocol Selection And Non-HTTP Routing
   - Lab: Declare A Service Port As HTTP Lab
13. Summary

### Scope Proxy Configuration With The Sidecar Resource

4 parts and 2 labs:

1. What Every Proxy Receives By Default
2. Limit Egress Hosts With A Namespace-Wide Sidecar
   - Lab: Limit A Namespace's Proxy Configuration With A Sidecar Lab
3. Which Sidecar Applies To A Workload
   - Lab: Repair A Workload-Selected Sidecar Lab
4. What A Sidecar Resource Cannot Enforce
5. Summary

### Apply And Remove Traffic Rules Safely

2 parts and 1 lab:

1. Apply And Remove Objects In Dependency Order
   - Lab: Retire A Subset Without Failed Requests Lab
2. One Object Per Host And Istio's Defaults
3. Summary

### Capstone

The section ends with a capstone lab that uses everything in it: **Route With Subsets And Scope Proxies With A Sidecar Capstone Lab**.

---

<!-- astrona:playground:environment-explain -->
