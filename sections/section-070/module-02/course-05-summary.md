# Summary

When an application encrypts its own HTTPS call, its sidecar proxy cannot read the request. The proxy sees only the destination address, the SNI (Server Name Indication) name, the byte counts and whether the connection worked. The access log shows `"- - -"` and status `0` for such a connection. Plain HTTP to a host that is not in the service registry looks the same, because the proxy only parses HTTP on a port it knows carries HTTP. On an encrypted stream, only connection-level policy, such as a TCP connection pool limit, still works.

TLS (Transport Layer Security) origination lets the application send plain HTTP while its sidecar proxy adds TLS on the way out. It needs three objects. The `ServiceEntry` declares the external host with two ports: `80` as `HTTP` and `443` as `HTTPS`. The `VirtualService` matches port `80` and routes to the same host on port `443`. The `DestinationRule` sets `tls.mode: SIMPLE` and `sni` under `portLevelSettings` for port `443` only. Each missing object has its own symptom: raw bytes or plain HTTP on port `80`, or a `400` from the server when plain HTTP reaches the TLS port.

Two mistakes pass `kubectl apply` without a warning. A top-level `tls` in `trafficPolicy` turns on TLS for every port, including port `80`. The redirect hides it, but any request that stays on port `80` fails with `503 UF` and `WRONG_VERSION_NUMBER`. An application that still calls `https://` gets its request encrypted twice, and `curl` fails with exit code `35`.

A `200` alone does not prove TLS origination. The proof comes from both ends: the destination reports the `https` scheme, and the proxy's cluster for port `443` has the `envoy.transport_sockets.tls` transport socket with the `sni` name. Once the proxy can read the requests, request-level features such as a route `timeout` work for the external service again.

`MUTUAL` TLS adds a client certificate. The proxy reads it from file paths inside the proxy container, or from a Kubernetes secret named in `credentialName`. An egress gateway can keep that certificate in one place instead of in every calling namespace.

Key facts:

- Without `sni`, Istio sets `autoSni` and takes the server name from the `Host` header.
- `IST0129` warns that no `caCertificates` are set; the proxy then uses its default trust store.
- On a sidecar, `credentialName` reads the secret from the namespace of the calling workload.
- `insecureSkipVerify: true` turns off the server certificate check and belongs only in tests.

<!-- astrona:playground:destroy -->
