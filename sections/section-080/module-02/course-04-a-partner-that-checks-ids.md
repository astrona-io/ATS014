# A Partner That Checks IDs

Some partners are stricter than `httpbin.org`. Before they answer, they check two things: that you reached the right server, and who you are. In this part you route signals to such a partner through the departure gate, and you watch the TLS handshake fail on both checks, one after the other.

The commands below need the `Gateway` `departure-gate`, the `DestinationRule` `departure-gate` and the helpers from the landing page in your playground.

## Two IDs in one handshake

A TLS handshake can check an ID in each direction. Think of two ships docking: each crew may ask to see the other ship's papers before the airlock opens.

| Who shows an ID | Who checks it | Called |
| --- | --- | --- |
| the server | the caller, here the gate | the **server certificate**, checked in every TLS handshake |
| the caller, here the gate | the server | the **client certificate**, only when the server asks for it |

When both sides show and check an ID, the handshake is **mutual TLS**. `tls.mode: SIMPLE` only covers the first row. It checks the server's certificate against a list of trusted **certificate authorities**: the organisations that sign IDs, like a passport office. By default the gate trusts the same authorities as its operating system, the ones the public internet uses.

The partner in your playground, `partner.outpost.example`, signs its own IDs with a private authority, the "Outpost Root CA". The public list does not know it. And the partner asks every caller for a client certificate.

## Route the partner through the gate

The partner needs the same four routing objects as `httpbin.org`. Two of them are new. The other two are the gate's `Gateway` and `DestinationRule`, which each get one more line for the new host.

<!-- astrona:playground:renew -->

### Put the partner on the star chart

The partner runs on the planet `outpost`, outside the mesh. Its `ServiceEntry` gives it the outside name `partner.outpost.example`, and `endpoints` says where the signals really go: the partner's own address in the cluster. Save this as `serviceentry-partner.yaml`:

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

### Open the gate for the partner

The gate must also carry signals for the partner. Add the host to the `Gateway`. Save this as `gateway-departure-gate.yaml`, replacing the earlier version:

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

Stage 1 for the partner needs its own empty subset of the gate's Service. Save this as `destinationrule-departure-gate.yaml`, replacing the earlier version:

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

### Write the partner's flight plan

The same two stages as before: in every sidecar, port `80` flies to the gate; on the gate, the signal flies on to the partner on port `443`. Save this as `virtualservice-partner-via-gate.yaml`:

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

## The first check: the server's ID

Now add the lock, exactly as for `httpbin.org`: `SIMPLE` on port `443`, with the partner's name as `sni`, and `exportTo` so only the gate gets it.

### Seal the partner's signals

Save this as `destinationrule-partner-tls.yaml`:

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

Then call the partner and read the gate's flight log:

```sh
call_partner
log_gate
```

You should see (the log line trimmed):

```text
upstream connect error or disconnect/reset before headers. retried and the latest reset reason: remote connection failure503
"GET / HTTP/2" 503 URX,UF upstream_reset_before_response_started{remote_connection_failure|TLS_error:|268435581:SSL_routines:OPENSSL_internal:CERTIFICATE_VERIFY_FAILED:verify_cert_failed:_X509_verify_cert:_certificate_verification_error_at_depth_0:_unable_to_get_local_issuer_certificate:TLS_error_end} ... "partner.outpost.example" "10.96.110.203:443" outbound|443||partner.outpost.example ...
```

The gate refused the partner. `CERTIFICATE_VERIFY_FAILED` with `unable_to_get_local_issuer_certificate` means the gate could not find the authority that signed the partner's ID in its trusted list. That is the gate doing its job: it does not hand your signal to a server it cannot identify.

## The second check: your ID

To reach the next check, tell the gate to skip the server check for a moment. The field `insecureSkipVerify: true` does that. It is only a test step: it means the gate would hand your signal to anyone who answers on that address.

### Skip the server check for one test

This adds one field, so a short `kubectl patch` is enough:

```sh
kubectl patch destinationrule partner-tls -n starfleet --type json \
  -p '[{"op":"add","path":"/spec/trafficPolicy/portLevelSettings/0/tls/insecureSkipVerify","value":true}]'
```

Then call the partner again:

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

The handshake now gets through, and the partner answers. But it answers `400`: the partner asked for a client certificate, and the gate had none to show. Both checks need the same fix: give the gate the partner's authority to trust, and an ID of its own to show.

## Common pitfalls

> [!WARNING]
> - **A server signed by a private authority with only `SIMPLE`.** The gate checks against the public authorities and fails with `CERTIFICATE_VERIFY_FAILED`. Give it the partner's authority instead.
> - **Keeping `insecureSkipVerify: true`.** It switches the server check off for good. Use it to test one step, never as the fix.
> - **Forgetting the partner's host in the `Gateway`.** The gate then has no route for it. Each outside host the gate carries is listed in `hosts`.
> - **Reading the `400` as a routing problem.** The answer came from the partner itself, after the handshake. The route works; the gate is missing its ID.

> *`SIMPLE` checks the server's ID. A partner that also checks yours needs `MUTUAL`, and the gate needs both IDs on board.*
