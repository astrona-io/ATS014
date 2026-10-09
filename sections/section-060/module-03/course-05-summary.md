# Summary

The Kubernetes Gateway API is a standard set of objects for bringing requests from outside the cluster into it. It comes as custom resource definitions (CRDs), installed separately from Kubernetes and from Istio. When the CRDs are missing, `kubectl apply` fails with `no matches for kind "Gateway"`. That error comes from the Kubernetes API server, not from Istio.

The API splits the work into three objects with three owners. The cluster-wide `GatewayClass` names the controller that builds gateways; Istio registers the class `istio` with the controller `istio.io/gateway-controller`. The namespaced `Gateway` describes the listeners: port, protocol, host name, and which routes may attach. The namespaced `HTTPRoute` sends matching requests to a Service. Istio's own `Gateway` (`networking.istio.io`) shares only its kind name with the Gateway API `Gateway` (`gateway.networking.k8s.io`), so always check the `apiVersion`.

A Gateway API `Gateway` with `gatewayClassName: istio` does not configure an existing proxy. Istio deploys a new Envoy proxy for it: a Deployment and a Service named `<gateway name>-istio`, in the `Gateway`'s own namespace. The proxy has the same life as the object, so deleting the `Gateway` deletes the proxy. On a `kind` cluster, the annotation `networking.istio.io/service-type: ClusterIP` gives the Service an address; without it, the `Gateway` stays `Programmed=False`. A gateway with no matching route answers `404` with the response flag `NR`.

An `HTTPRoute` attaches with `parentRefs`, selects requests with `hostnames` and `matches`, and names a Service and port in `backendRefs`. `PathPrefix` matches whole path segments, unlike Istio's `uri.prefix`. Weights and filters cover traffic shifting, header changes, redirects and rewrites. Subsets, load balancing, connection pools and outlier detection stay in a `DestinationRule`, which applies to a Service whichever object routed the request there.

Status conditions tell you which object to fix. On a `Gateway`, `Accepted` means the controller took the object, and `Programmed` means the gateway has an address. On an `HTTPRoute`, the conditions are listed per parent gateway: `Accepted` is about the gateway side, and `ResolvedRefs` is about the backend side. A typo in `backendRefs` gives `ResolvedRefs=False BackendNotFound` and `500 NC` responses. A typo in `parentRefs` gives an empty `status.parents`, because no gateway answers for the route.

The owner of a `Gateway` controls which namespaces may attach routes with `allowedRoutes`. The default, `Same`, allows only the `Gateway`'s own namespace, and a route from another namespace gets `Accepted=False NotAllowedByListeners`. A `Selector` allows only namespaces with a chosen label, and that includes the `Gateway`'s own namespace. A route in another namespace must also name the `Gateway`'s namespace in `parentRefs`.

Key facts to remember:

- Gateway API kinds: `GatewayClass` (cluster), `Gateway` and `HTTPRoute` (namespace).
- Istio's proxy for a Gateway API `Gateway`: `<gateway name>-istio`, in the `Gateway`'s namespace.
- `Gateway` conditions: `Accepted`, `Programmed`. `HTTPRoute` conditions: `Accepted`, `ResolvedRefs`.
- Empty `status.parents` means a wrong name or namespace in `parentRefs`.
- `allowedRoutes.namespaces.from`: `Same` (default), `All`, `Selector`.

<!-- astrona:playground:destroy -->
