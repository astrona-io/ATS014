# Summary

An egress gateway is an Envoy proxy that outbound traffic to outside hosts can be sent through, so the traffic leaves the mesh at one point. It runs in its own pod behind its own Service. The Helm `gateway` chart labels its pods `istio: egress`, and the `demo` profile labels them `istio: egressgateway`.

A running egress gateway carries no traffic by itself. Without routing, every sidecar proxy sends outbound requests straight to the outside host, and the egress gateway's access log stays empty. A client connects to an ingress gateway on purpose, but routing must choose the egress gateway.

Three objects prepare the route. A `ServiceEntry` adds the outside host to the service registry. A `Gateway` makes the egress gateway accept that host, and its `servers[].hosts` names the **outside** host, read from the gateway's point of view. A `DestinationRule` on the egress gateway's Service defines a subset with no labels. The subset narrows nothing, but hop 1 names it, so it must exist. For HTTPS, `tls.mode: PASSTHROUGH` forwards the encrypted stream without decrypting it, and the gateway gets no listener until a `VirtualService` routes the host through it.

One `VirtualService` holds both hops. Hop 1 is the rule for `mesh`, the reserved name for every sidecar proxy, and sends the request to the egress gateway's subset. Hop 2 is the rule for the egress gateway and sends the request to the real host. The top-level `gateways` list must name both, and each rule's `match.gateways` says which proxy runs it. HTTPS needs `tls` rules that match on `sniHosts`, the host name from the TLS handshake. Plain HTTP uses `http` rules that match on the port.

A `200` proves nothing, because a request that skips the egress gateway also succeeds. The proof is in two access logs: the client's sidecar log shows where hop 1 went, and the egress gateway's log shows whether hop 2 happened. Each broken object leaves its own pattern in those logs.

`sourceLabels` on hop 1 sends only the pods with a given label through the egress gateway. It limits the route, not the permission: a pod without the label still reaches the outside host directly. Real egress control needs the route, `outboundTrafficPolicy: REGISTRY_ONLY`, and an `AuthorizationPolicy` on the egress gateway plus a Kubernetes `NetworkPolicy`. The egress gateway gives one access log, one source address and one place for policy and certificates. It costs an extra hop, more configuration per host, and a component that every outbound request depends on.

Key facts to remember:

- `mesh` missing from the top-level `gateways`: `200`, the request goes straight out, and `istioctl analyze` reports nothing.
- Hop 2 missing, or a `Gateway` that does not serve the host: the egress gateway has no listener, and the client's sidecar logs `UF,URX` with `Connection_refused` (`IST0132` for the `Gateway`).
- `DestinationRule` missing: `NC` in the client's sidecar log, and `IST0101` from `istioctl analyze`.
- On Istio 1.30.5, a `tls` hop 1 needs `gateways: [mesh]` next to `sourceLabels`; an `http` hop 1 must leave `gateways` out of its `match`.

<!-- astrona:playground:destroy -->
