# Summary

TLS origination means that a proxy, not the application, opens the TLS connection to an external server. When the egress gateway does it, the application sends plain `http://`, the sidecar proxy sends the request to the egress gateway on port `80`, and the egress gateway sends it on to port `443` of the external host with TLS. The two port numbers describe two directions: where the egress gateway listens, and where it sends.

Five objects build this path. A `ServiceEntry` adds the external host with both ports. A `Gateway` opens port `80` on the egress gateway for that host. A `DestinationRule` on the egress gateway's own Service defines the empty subset that the first routing rule sends to. A `VirtualService` holds both rules: the `mesh` rule in every sidecar proxy, and the `Gateway` rule in the egress gateway. The fifth object, a `DestinationRule` for the external host, turns on TLS.

A `DestinationRule` is applied by the proxy that calls the host it names. The egress gateway calls the external host, so the TLS settings go in a `DestinationRule` for that host, under `portLevelSettings` for port `443`, with `tls.mode: SIMPLE` and `sni`. TLS settings on the egress gateway's own Service go to the sidecar proxy instead, which then tries TLS on a plain port and fails with `503 URX,UF` and `WRONG_VERSION_NUMBER`.

A `200` alone proves little. If the second rule routes to port `80`, the TLS settings are never used, and a server that also speaks plain HTTP still answers. The proof comes from the egress gateway's access log (upstream port `443`), from the `https://` the server reports, and from counting the `transportSocket` in each proxy's cluster for the host. By default a `DestinationRule` reaches every proxy in the mesh; `exportTo` with the egress gateway's namespace keeps the TLS settings on the egress gateway alone.

A TLS handshake can check a certificate in each direction. `SIMPLE` checks the server certificate against public certificate authorities, so a server with a private CA fails with `CERTIFICATE_VERIFY_FAILED`. A server that asks for a client certificate needs `tls.mode: MUTUAL` with `credentialName`, which names a `Secret` with `tls.crt`, `tls.key` and `ca.crt`. `istiod` sends it to the proxy over SDS, and it reads the `Secret` from the namespace of the proxy that uses it.

Key facts to remember:

- The TLS `DestinationRule` names the external host, not the egress gateway's Service.
- `gate: 1`, `shuttle: 0` for `transportSocket` proves the egress gateway starts TLS.
- `insecureSkipVerify: true` is a test step, never the fix.
- `Secret_is_not_supplied_by_SDS` and `WARMING` in `istioctl proxy-config secret` point at a missing `Secret`; the `istiod` log names the namespace it looked in.
- TLS at the egress gateway keeps the client certificate in one place, at the cost of an extra hop, more objects, and one component every outgoing request depends on.

<!-- astrona:playground:destroy -->
