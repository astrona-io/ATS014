# Summary

Requests from outside the cluster enter the mesh through the ingress gateway. It is the same Envoy proxy that runs as every sidecar proxy, but it runs alone in its own pod (`1/1`), in its own namespace, behind a Kubernetes Service. On a `kind` cluster that Service gets no external address, so you reach it through a port forward.

Two objects configure the gateway. A `Gateway` opens a listener on the gateway pods that its `selector` matches, for a port, a protocol and a list of hosts. It holds no destination and routes nothing by itself. The right selector label depends on the install: `istio: ingress` for the Helm chart installed as `istio-ingress`, and `istio: ingressgateway` for an `istioctl` install.

A `VirtualService` gives the gateway its routes, but only when its `gateways:` field names the `Gateway`. Without that field, the `VirtualService` gets the default value `mesh`, so `istiod` sends the routes to the sidecar proxies and the gateway keeps answering `404 NR`. `istioctl analyze` does not report this, because a `VirtualService` for `mesh` is valid. Naming a gateway replaces `mesh`, so list both when sidecar proxies need the same routes.

The names on the two objects must line up. The gateway uses a `VirtualService` only for the hosts where both host lists overlap, and a `*` on one side does not fix a wrong host on the other. A bare `Gateway` name is looked up in the `VirtualService`'s own namespace, so a `Gateway` in another namespace needs `<namespace>/<name>`. Behind the gateway, routes work exactly as in the mesh, with subsets, weights, retries and faults.

When the gateway fails, the status code says which object to check. `000` means no listener, so check the `Gateway` selector. `404` with the response flag `NR` means no matching route, so check hosts, `gateways:` and paths. `503` with `NC` or `UH` means a route matched but the destination is missing or has no healthy pod. The gateway's access log, its listeners, routes and endpoints, and `istioctl analyze` confirm each case.

Key facts to remember:

- A `Gateway` with the wrong selector gives `000`, no port `80` listener, and `IST0101 Referenced selector not found`.
- A correct `Gateway` with no bound `VirtualService` gives `404 NR` from an empty route table `http.80`.
- A host that the `Gateway` does not serve gives `404` and the warning `IST0132`.
- A destination host that does not exist gives `503 NC cluster_not_found` and `IST0101 Referenced host not found`.
- Always send the `Host` header when you test a gateway with curl.

<!-- astrona:playground:destroy -->
