# Summary

Istio knows only the hosts in its service registry: the Kubernetes Services in the cluster, plus every `ServiceEntry` and `WorkloadEntry`. The outbound traffic policy decides what the sidecar proxy does with a request to any other host. Under `ALLOW_ANY`, the default, the proxy lets it through as `PassthroughCluster`, with no rules and no record of the host. Under `REGISTRY_ONLY`, the proxy refuses it as `BlackHoleCluster`.

You set the policy for the whole mesh with `meshConfig.outboundTrafficPolicy.mode` when you install the control plane, or for one namespace with `outboundTrafficPolicy` on a `Sidecar` resource. A refusal never names the policy. It shows as a closed connection (`000`, with `curl` exit code `35` or `56`), or as a `502` from the `block_all` route when the proxy already has an HTTP listener on that port. The access log tells a refusal apart from a DNS or network failure. The sidecar proxy enforces the policy, so a pod without a sidecar is not limited.

A `ServiceEntry` adds an external host to the registry with four answers: `hosts`, `ports` with a `protocol`, `location` and `resolution`. The declared protocol decides how much of Istio applies. Only `HTTP` lets the proxy read requests; `HTTPS` and `TLS` let it read only the SNI host name, and `TCP` only moves bytes. `MESH_EXTERNAL` is for somebody else's API, and `MESH_INTERNAL` is for your own workloads outside Kubernetes. `resolution: DNS` shows as `STRICT_DNS` in the proxy, and a wildcard host needs `resolution: NONE`.

Once a host is in the registry, a `VirtualService` and a `DestinationRule` work on it as on any Service in the cluster. A timeout on a port declared `HTTP` ends a slow request with `504` and the `UT` flag. A connection pool becomes Envoy circuit breaker limits, and requests over the limit fail at once with `503` and the `UO` flag. A route to a port that is not in the registry gives `IST0101` in `istioctl analyze`.

A correct `ServiceEntry` works only for a caller that may see it. Its `exportTo` must include the caller's namespace, and the caller's `Sidecar` `egress.hosts` must take in the entry's namespace. A hidden entry gives the same refusal as a missing one, and `istioctl analyze` stays quiet, because each object is valid on its own. `istioctl proxy-config cluster` on the calling pod shows whether its proxy has the host.

Key facts to remember:

- `ALLOW_ANY` is the install default; `REGISTRY_ONLY` blocks every host outside the registry.
- `PassthroughCluster` means let through, `BlackHoleCluster` and `block_all` mean refused, `outbound|443||<host>` means the host came from a `ServiceEntry`.
- HTTP features on an external host need a port declared `protocol: HTTP`.
- A `ServiceEntry` is exported to every namespace unless `exportTo` says otherwise.
- The safe default under `REGISTRY_ONLY`: put the entry in the namespace of the pods that use it, with `exportTo: ["."]`.

<!-- astrona:playground:destroy -->
