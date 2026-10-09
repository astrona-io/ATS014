# Summary

Istio works through a sidecar proxy, Envoy, in every pod of the mesh. Sidecar injection adds it: a namespace with the label `istio-injection: enabled` makes the mutating admission webhook add the `istio-init` and `istio-proxy` containers to every new pod. Pods that were already running do not change until they restart.

On recent Kubernetes versions, `istio-proxy` is a native sidecar, an init container with `restartPolicy: Always`, so a pod with one application container shows `2/2`. A pod that shows `1/1` where you expected `2/2` has no proxy, and no Istio rule can reach it.

The application never connects to the proxy on purpose. The `iptables` rules that `istio-init` writes send outgoing connections to port `15001` and incoming connections to port `15006` of the proxy. The proxy then opens its own connection to the destination.

A request between two meshed pods passes two proxies and appears in two access logs: an `outbound` line from the client's proxy and an `inbound` line from the server's proxy. The client's proxy decides routing, retries and timeouts, so a client without a proxy still reaches the mesh but gets none of these rules.

The configuration comes from `istiod`, the control plane. It builds the service registry from Services, EndpointSlices, pods and Istio objects, and pushes configuration to every proxy over xDS while the proxy runs. By default every proxy holds configuration for every Service in the mesh.

Inside the proxy, a request passes four layers in order: a listener accepts it by port, a route picks a host, a cluster names the destination, and an endpoint is the pod address. A cluster name such as `outbound|8000||probe.starfleet.svc.cluster.local` gives the direction, the Service port, the subset and the host. The cluster carries the Service port, while the endpoint carries the container port.

When something goes wrong, check in a fixed order and stop at the first step that disagrees with what you expect. An object that exists is not yet an object that a proxy acts on. The response flag in the access log tells the failures apart.

Key facts to remember:

- LDS, RDS, CDS and EDS are the Listener, Route, Cluster and Endpoint Discovery Services; SDS delivers certificates.
- `kubectl apply` stores an object; `istioctl proxy-status` shows whether the proxies received it.
- The order of checks is `kubectl get`, `istioctl analyze`, `istioctl proxy-status`, `istioctl proxy-config`, then the access log.
- A clean `istioctl analyze` does not prove that your labels select any pod.
- `NR` comes with a `404` and points at routing; `NC` and `UH` come with a `503` and point at the destination.

<!-- astrona:playground:destroy -->
