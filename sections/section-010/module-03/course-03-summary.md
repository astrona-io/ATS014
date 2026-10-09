# Summary

This module was about *when* your rules reach the proxies, not what they say. Correct objects can still break requests if they reach the proxies in the wrong order.

The `VirtualService` and the `DestinationRule` are read by the sidecar proxy of the pod that **sends** the request. At the edge of the mesh, a gateway proxy reads them instead. `istiod` pushes each object to every proxy over xDS, and for a short time some proxies have the new configuration while others still have the old one.

The safe order follows the pointers. Create the object that is pointed at first: `ServiceEntry`, then `DestinationRule`, then `Gateway`, then `VirtualService`. Remove in the reverse order, pointer first. This is "make before break": if a route reaches a proxy before the subset it names, the proxy answers `503 NC` ("no cluster") by itself, and `istioctl analyze` reports `IST0101`. A `Sidecar` can be applied at any time, but every host the applications call must stay in its `egress.hosts` list.

`kubectl apply` returns when Kubernetes has stored the object, not when the proxies have it. Before you test, check that the configuration arrived: `istioctl proxy-status` for the connection to `istiod`, `istioctl proxy-config clusters` on the client for the new subset, and `istioctl analyze` for objects that do not agree.

Two files with the same kind, `metadata.name` and namespace describe one object, so `kubectl apply` replaces it and prints `configured`. Two objects with different names for the same host have no defined order, so keep one `VirtualService` and one `DestinationRule` per host.

Key facts to remember:

- With no rules, Istio has no HTTP timeout.
- The default retry policy retries connection failures 2 times, but never an application's own `503`.
- The default load balancing is `LEAST_REQUEST`, unknown outside hosts are let through (`ALLOW_ANY`), and circuit breaker limits are in practice unlimited.
- `NC`, `UH`, `UO` and `URX` all reach the client as `503`. Read the response flag in the access log, not just the status code.

<!-- astrona:playground:destroy -->
