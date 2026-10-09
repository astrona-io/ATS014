# Server And Client Certificates In The TLS Handshake

Some external servers are stricter than `httpbin.org`. Before they answer, they check two things: that the caller reached the right server, and who the caller is. In this part you route requests from the `shuttle` pod to such a server through the egress gateway. You then watch the TLS (Transport Layer Security) handshake fail on each of the two checks, one after the other, and learn to read each failure.

The commands below need the `Gateway` `departure-gate` and the `DestinationRule` `departure-gate` applied in your playground, and the helper functions `call_partner` and `log_gate` defined in your terminal.

## Two certificates in one handshake

A TLS handshake can check a certificate in each direction:

| Who presents a certificate | Who checks it | Name |
| --- | --- | --- |
| the server | the caller, here the egress gateway | the **server certificate**, checked in every TLS handshake |
| the caller, here the egress gateway | the server | the **client certificate**, sent only when the server asks for it |

When both sides present and check a certificate, the handshake is **mutual TLS**. `tls.mode: SIMPLE` only covers the first row. It checks the server's certificate against a list of trusted **certificate authorities** (CAs): the organisations whose signature on a certificate the caller accepts. By default the egress gateway trusts the same CAs as its operating system, the public CAs that most internet servers use.

The partner server in your playground, `partner.outpost.example`, has a certificate signed by a private CA, the "Outpost Root CA". The public list does not contain it. The partner server also asks every caller for a client certificate.

## Route the partner server through the egress gateway

The partner server needs the same four routing objects as `httpbin.org`. Two of them are new. The other two are the `Gateway` and the `DestinationRule` for the egress gateway's Service, which each get one more entry for the new host.

<!-- astrona:playground:renew -->

The partner server runs in the namespace `outpost`, outside the mesh. Its `ServiceEntry` gives it the external name `partner.outpost.example`, and `endpoints` says where the requests really go: the partner server's own Service address in the cluster. Save this as `serviceentry-partner.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: ServiceEntry
metadata:
  name: partner
  namespace: starfleet
spec:
  hosts:
  - partner.outpost.example
  ports:
  - number: 80
    name: http
    protocol: HTTP
  - number: 443
    name: https
    protocol: HTTPS
  location: MESH_EXTERNAL
  resolution: DNS
  endpoints:
  - address: partner.outpost.svc.cluster.local
```

Apply it:

```sh
kubectl apply -f serviceentry-partner.yaml
```

The egress gateway must also accept requests for the partner server, so add the host to the `Gateway`. Save this as `gateway-departure-gate.yaml`, replacing the earlier version:

```yaml
apiVersion: networking.istio.io/v1
kind: Gateway
metadata:
  name: departure-gate
  namespace: starfleet
spec:
  selector:
    istio: egress
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - httpbin.org
    - partner.outpost.example
```

Apply it:

```sh
kubectl apply -f gateway-departure-gate.yaml
```

Rule 1 for the partner server needs its own empty subset of the egress gateway's Service. Save this as `destinationrule-departure-gate.yaml`, replacing the earlier version:

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: departure-gate
  namespace: starfleet
spec:
  host: istio-egress.istio-egress.svc.cluster.local
  subsets:
  - name: httpbin-org
  - name: partner
```

Apply it:

```sh
kubectl apply -f destinationrule-departure-gate.yaml
```

The `VirtualService` has the same two rules as for `httpbin.org`. In every sidecar proxy, port `80` goes to the egress gateway. On the egress gateway, the request goes on to the partner server on port `443`. Save this as `virtualservice-partner-via-gate.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: partner-via-gate
  namespace: starfleet
spec:
  hosts:
  - partner.outpost.example
  gateways:
  - mesh
  - departure-gate
  http:
  - match:
    - gateways:
      - mesh
      port: 80
    route:
    - destination:
        host: istio-egress.istio-egress.svc.cluster.local
        subset: partner
        port:
          number: 80
  - match:
    - gateways:
      - departure-gate
      port: 80
    route:
    - destination:
        host: partner.outpost.example
        port:
          number: 443
```

Apply it:

```sh
kubectl apply -f virtualservice-partner-via-gate.yaml
```

## The first check: the server certificate

Now turn on TLS, exactly as for `httpbin.org`: `SIMPLE` on port `443`, the partner's host name as `sni`, and `exportTo` so that only the egress gateway gets the rule. Save this as `destinationrule-partner-tls.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: partner-tls
  namespace: starfleet
spec:
  host: partner.outpost.example
  exportTo:
  - istio-egress
  trafficPolicy:
    portLevelSettings:
    - port:
        number: 443
      tls:
        mode: SIMPLE
        sni: partner.outpost.example
```

Apply it:

```sh
kubectl apply -f destinationrule-partner-tls.yaml
```

Then call the partner server and read the egress gateway's access log:

```sh
call_partner
log_gate
```

You should see (log line shortened):

```text
upstream connect error or disconnect/reset before headers. retried and the latest reset reason: remote connection failure503
"GET / HTTP/2" 503 URX,UF upstream_reset_before_response_started{remote_connection_failure|TLS_error:|268435581:SSL_routines:OPENSSL_internal:CERTIFICATE_VERIFY_FAILED:verify_cert_failed:_X509_verify_cert:_certificate_verification_error_at_depth_0:_unable_to_get_local_issuer_certificate:TLS_error_end} ... "partner.outpost.example" "10.96.110.203:443" outbound|443||partner.outpost.example ...
```

The egress gateway rejected the partner server. `CERTIFICATE_VERIFY_FAILED` with `unable_to_get_local_issuer_certificate` means the egress gateway could not find the CA that signed the server certificate in its trusted list. This is the check working as intended: the egress gateway does not send your request to a server it cannot verify.

## The second check: the client certificate

To reach the second check, tell the egress gateway to skip the server check for one test. The field `insecureSkipVerify: true` does that. Use it only as a test step: with it, the egress gateway sends your request to any server that answers on that address. This adds one field, so a short `kubectl patch` is enough:

```sh
kubectl patch destinationrule partner-tls -n starfleet --type json \
  -p '[{"op":"add","path":"/spec/trafficPolicy/portLevelSettings/0/tls/insecureSkipVerify","value":true}]'
```

Then call the partner server again:

```sh
call_partner
```

You should see:

```text
<html>
<head><title>400 No required SSL certificate was sent</title></head>
<body>
<center><h1>400 Bad Request</h1></center>
<center>No required SSL certificate was sent</center>
<hr><center>nginx/1.27.5</center>
</body>
</html>
400
```

The handshake now completes, and the partner server answers. But it answers `400`: it asked for a client certificate, and the egress gateway had none to send.

You now know the two checks of a TLS handshake and the failure each one gives at the egress gateway: `CERTIFICATE_VERIFY_FAILED` when the egress gateway cannot verify the server, and `400 No required SSL certificate was sent` when the server gets no client certificate. Both checks need the same fix. The egress gateway needs the partner's CA to trust, and a client certificate of its own to present. How to give it both is the open question.

## Common pitfalls

> [!WARNING]
> - **A server signed by a private CA with only `SIMPLE`.** The egress gateway checks against the public CAs and fails with `CERTIFICATE_VERIFY_FAILED`. Give it the partner's CA instead.
> - **Keeping `insecureSkipVerify: true`.** It switches the server check off for good. Use it to test one step, never as the fix.
> - **Forgetting the partner's host in the `Gateway`.** The egress gateway then has no route for it. List each external host the egress gateway accepts in `hosts`.
> - **Reading the `400` as a routing problem.** The response came from the partner server itself, after the handshake. The route works; the client certificate is missing.
