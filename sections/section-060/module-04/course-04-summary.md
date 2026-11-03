# Summary

An ingress gateway terminates HTTPS with a `tls` block on a `Gateway` server. The server uses `protocol: HTTPS` and `tls.mode: SIMPLE`, and `credentialName` names the secret that holds the certificate and the private key. `istiod` reads that secret and sends it to the gateway over SDS. The secret has the type `kubernetes.io/tls`, with the keys `tls.crt` and `tls.key`, and it must be in the namespace of the gateway pod, not in the namespace of the `Gateway`. `kubectl create secret tls` builds it from two files.

You prove the result in three ways. A request with `curl -k --resolve host:8443:127.0.0.1` sends the host name as SNI, which the gateway needs to choose a certificate. `openssl s_client` shows which certificate the gateway sent. `istioctl proxy-config secret` shows `kubernetes://<name>` as `ACTIVE` when the gateway holds the certificate, and as `WARMING` when `istiod` cannot find the secret.

A server on port 80 with `tls.httpsRedirect: true` answers every plain HTTP request with a `301` that points to the same host and path over HTTPS. Several hosts share port 443 as separate servers, each with its own `name` and its own `credentialName`. SNI picks the certificate before any HTTP request exists. A secret that is missing, in the wrong namespace or named differently from `credentialName` fails quietly: the secret stays `WARMING`, and that host cannot finish a TLS handshake.

`tls.mode: MUTUAL` makes the gateway ask the client for a certificate and check it against a CA. The secret then needs a third key, `ca.crt`, so it is a generic secret with `tls.crt`, `tls.key` and `ca.crt`. A client with no certificate, or with a certificate from another CA, cannot connect.

`tls.mode: PASSTHROUGH` makes the gateway forward the encrypted connection by SNI, without a certificate and without decrypting it. The server uses `protocol: TLS`, and the backend terminates TLS itself. Because the gateway cannot read the request, the `VirtualService` must use a `tls:` match on `sniHosts`. A `VirtualService` that has only `http:` rules does not apply to such a server.

Key facts:

- TLS secret for `SIMPLE`: type `kubernetes.io/tls`, in the namespace of the gateway pod.
- `MUTUAL` secret: `tls.crt`, `tls.key` and `ca.crt`.
- Redirect: `tls.httpsRedirect: true` on the port 80 server.
- `PASSTHROUGH`: `protocol: TLS` on the server, `tls:` with `sniHosts` in the `VirtualService`.
- Check certificates with `openssl s_client -servername` and `istioctl proxy-config secret`.

<!-- astrona:playground:destroy -->
