# Summary

By default, `istiod` gives every sidecar proxy a cluster for every host in the service registry, whether or not the application in that pod ever calls it. `istiod` pushes each change over xDS to every running proxy, without a pod restart. The cost grows as the number of proxies times the number of destinations: proxy memory, `istiod` CPU and push delay. The default also means that every pod can reach every Service, as a side effect that nobody chose.

The `Sidecar` resource limits that configuration. It has four fields: `workloadSelector`, `egress[].hosts`, `outboundTrafficPolicy` and `ingress`. Without a selector it applies to every pod in its namespace, and by convention it is called `default`. Hosts are written as `<namespace>/<host>`, where the namespace half names where the target host lives. `./*` means the pod's own namespace, and `./*` plus `istio-system/*` is the minimum of every namespace-wide `Sidecar`.

You prove a `Sidecar` without sending traffic: the host and its listener disappear from `istioctl proxy-config`. Under the default `ALLOW_ANY`, a request for an unknown host still leaves through `PassthroughCluster` as raw TCP bytes. With `outboundTrafficPolicy` set to `REGISTRY_ONLY`, the proxy sends it to the `BlackHoleCluster`: `curl` reports `000` and the access log shows `UH`.

Only one `Sidecar` applies to a pod. `istiod` uses a selector `Sidecar` first, then the namespace-wide one, then a root `Sidecar` in `istio-system`. The winner replaces the others completely, including `istio-system/*` and `outboundTrafficPolicy`. So a selector `Sidecar` must list every host it needs again.

A `Sidecar` decides what a proxy knows, not what a workload accepts. It has no effect on pods without a sidecar proxy and never limits incoming traffic. For enforcement, combine it with `REGISTRY_ONLY`, an `AuthorizationPolicy` and a Kubernetes `NetworkPolicy`.

Key facts to remember:

- One namespace-wide `Sidecar` per namespace, plus selector `Sidecar` objects that never match the same pod twice.
- A merge patch of `egress[].hosts` replaces the whole list; it never adds to it.
- A host reaches a proxy only if its `exportTo` allows the namespace and the `Sidecar` in that namespace asks for it.
- When a host is missing, check the selector `Sidecar`, the namespace `Sidecar`, the root `Sidecar`, then `exportTo`.

<!-- astrona:playground:destroy -->
