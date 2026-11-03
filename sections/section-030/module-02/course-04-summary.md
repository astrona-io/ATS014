# Summary

The sidecar proxy of the calling pod decides how the connection to a destination is opened, and the `trafficPolicy.tls` field of a `DestinationRule` can tell it what to do. The four modes differ in what the client proxy does. `DISABLE` opens a plain connection. `SIMPLE` opens a TLS connection and sends no client certificate. `MUTUAL` sends a client certificate that you provide as files. `ISTIO_MUTUAL` opens an mTLS connection with the certificate that `istiod` gave to the proxy, and it is the mode for destinations inside the mesh.

When no `tls` block applies, automatic mTLS is in force: the client proxy opens an mTLS connection to every endpoint that has a sidecar proxy, and a plain connection to the others. An explicit `tls` block always replaces that automatic choice. The cluster dump from `istioctl proxy-config cluster -o json` shows the result as the TLS transport socket `envoy.transport_sockets.tls`: it is missing when the mode is `DISABLE`. The access log of the destination's proxy also shows which kind of connection arrived.

A `PeerAuthentication` with mode `STRICT` makes a workload accept only mTLS. A `DestinationRule` with `tls.mode: DISABLE` sends plain text to that workload, so the destination's proxy resets the connection and the client proxy answers `503`. The symptom is a reset connection, not a certificate message. The fix is `ISTIO_MUTUAL` or no `tls` block, and never a weaker `PeerAuthentication`. A client with no sidecar proxy cannot reach a `STRICT` workload, because no proxy reads a `DestinationRule` for it and it sends plain text.

A subset can carry its own `trafficPolicy`, and a port can carry its own settings in `portLevelSettings`. A subset keeps every top-level field it does not set, and a field it does set replaces the host's whole field with nothing merged inside it. A subset that sets only `loadBalancer` loses the host's `consistentHash` silently but keeps the host's `tls`. A port-level field replaces the host's field for that port, and it names the Service port. The cluster dump shows what each subset and port really got.

Key facts:

- No `tls` block means automatic mTLS to destinations with a sidecar.
- `ISTIO_MUTUAL` needs no certificate fields; `SIMPLE` and `MUTUAL` are for destinations whose certificates you manage.
- `DISABLE` against `STRICT` gives a reset connection and `503`.
- A subset replaces the host's fields it sets, as whole fields, and inherits the rest.
- `portLevelSettings` takes the Service port.

<!-- astrona:playground:destroy -->
