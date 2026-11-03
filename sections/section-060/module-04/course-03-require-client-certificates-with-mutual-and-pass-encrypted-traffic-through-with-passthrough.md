# Require Client Certificates With MUTUAL And Pass Encrypted Traffic Through With PASSTHROUGH

With `SIMPLE`, only the server proves who it is. Some services must also know who the client is, and some services must keep their own TLS connection with the client, without any proxy in the middle that can read it. The `Gateway` has a mode for each case. In this part you require a client certificate with `MUTUAL`, then pass an encrypted connection through unopened with `PASSTHROUGH`, and see why the second mode needs a different kind of route.

## `MUTUAL`: the client must present a certificate

With `tls.mode: MUTUAL`, the gateway terminates TLS like before, and it also asks the client for a certificate. It accepts the connection only if a certificate authority (CA) that it trusts signed that client certificate. This is mutual TLS (mTLS): both sides prove their identity.

The gateway needs the CA certificate to check the clients. So the secret behind `credentialName` holds three keys. A secret made with `kubectl create secret tls` has only the first two, so you make a generic secret instead:

| Key in the secret | What it is |
| --- | --- |
| `tls.crt` | the certificate the gateway presents to the client |
| `tls.key` | the private key of that certificate |
| `ca.crt` | the CA certificate that signed the client certificates |

Without `ca.crt`, the gateway has nothing to check a client against, and the handshake fails for every client.

## `PASSTHROUGH`: the gateway does not decrypt

With `tls.mode: PASSTHROUGH`, the gateway does not terminate TLS and has no certificate. It reads only the SNI from the start of the handshake, and then forwards the encrypted bytes to a backend that terminates TLS itself. It cannot see the path, the headers or the body. So a `VirtualService` cannot use `http:` rules for this traffic. It uses a `tls:` section with a `match` on `sniHosts` instead. A `VirtualService` that has only `http:` rules matches nothing on a passthrough server.

The commands below need the `Gateway` `starfleet-gateway` from the earlier steps (port 80 redirect and HTTPS servers for `starfleet.example.com` and `probe.example.com`), the secrets `starfleet-tls` and `probe-tls` in `istio-system`, and the `archive` Service in `starfleet`. The `archive` pod is an nginx server that has its own certificate for `archive.starfleet.example.com` and no sidecar proxy.

<!-- astrona:playground:renew -->

### Build a CA, a server certificate and a client certificate

Create a CA first. It is a self-signed certificate that you will use only to sign the client certificate:

```sh
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout ca.key -out ca.crt -subj "/CN=starfleet-ca/O=starfleet"
```

Then create the certificate for the gateway to present for `secure.starfleet.example.com`, and a client certificate signed by the CA. The client certificate is a request (`client.csr`) that the CA signs:

```sh
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout secure.key -out secure.crt -subj "/CN=secure.starfleet.example.com/O=starfleet"
openssl req -nodes -newkey rsa:2048 -keyout client.key -out client.csr -subj "/CN=shuttle-client/O=starfleet"
openssl x509 -req -in client.csr -CA ca.crt -CAkey ca.key -CAcreateserial -days 365 -out client.crt
```

Create the generic secret in `istio-system`, with the three keys:

```sh
kubectl create secret generic secure-tls -n istio-system \
  --from-file=tls.crt=secure.crt --from-file=tls.key=secure.key --from-file=ca.crt=ca.crt
```

### Add the `MUTUAL` and `PASSTHROUGH` servers

Replace `gateway-starfleet-gateway.yaml` with this file. It keeps the three servers you have and adds two more on port 443: one with `MUTUAL`, and one with `PASSTHROUGH`. The passthrough server uses `protocol: TLS`, not `HTTPS`, because the gateway does not speak HTTP on it:

```yaml
apiVersion: networking.istio.io/v1
kind: Gateway
metadata:
  name: starfleet-gateway
  namespace: starfleet
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - starfleet.example.com
    - probe.example.com
    tls:
      httpsRedirect: true
  - port:
      number: 443
      name: https-starfleet
      protocol: HTTPS
    hosts:
    - starfleet.example.com
    tls:
      mode: SIMPLE
      credentialName: starfleet-tls
  - port:
      number: 443
      name: https-probe
      protocol: HTTPS
    hosts:
    - probe.example.com
    tls:
      mode: SIMPLE
      credentialName: probe-tls
  - port:
      number: 443
      name: https-secure
      protocol: HTTPS
    hosts:
    - secure.starfleet.example.com
    tls:
      mode: MUTUAL
      credentialName: secure-tls
  - port:
      number: 443
      name: tls-archive
      protocol: TLS
    hosts:
    - archive.starfleet.example.com
    tls:
      mode: PASSTHROUGH
```

Apply it:

```sh
kubectl apply -f gateway-starfleet-gateway.yaml
```

### Route the two new hosts

The `MUTUAL` host is decrypted by the gateway, so its route is an ordinary `http:` rule. The `PASSTHROUGH` host has a `tls:` section that matches the SNI. Save this as `virtualservice-secure-and-archive.yaml`. It holds two objects:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: secure
  namespace: starfleet
spec:
  hosts:
  - secure.starfleet.example.com
  gateways:
  - starfleet-gateway
  http:
  - route:
    - destination:
        host: probe
        port:
          number: 8000
---
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: archive
  namespace: starfleet
spec:
  hosts:
  - archive.starfleet.example.com
  gateways:
  - starfleet-gateway
  tls:
  - match:
    - port: 443
      sniHosts:
      - archive.starfleet.example.com
    route:
    - destination:
        host: archive
        port:
          number: 443
```

Apply it:

```sh
kubectl apply -f virtualservice-secure-and-archive.yaml
```

### Test the client certificate

First send a request with no client certificate. Then send one with the certificate and key you created:

```sh
curl -sk -o /dev/null -w 'no client certificate: %{http_code}\n' --resolve secure.starfleet.example.com:8443:127.0.0.1 https://secure.starfleet.example.com:8443/get
curl -sk -o /dev/null -w 'with client certificate: %{http_code}\n' --cert client.crt --key client.key --resolve secure.starfleet.example.com:8443:127.0.0.1 https://secure.starfleet.example.com:8443/get
```

The first request prints `000`, because the gateway ends the handshake when the client sends no certificate. The second prints `200`. The gateway checked `client.crt` against `ca.crt` from the secret.

### Test the passthrough host

Send a request to the archive, and then ask for the certificate it presents:

```sh
curl -sk --resolve archive.starfleet.example.com:8443:127.0.0.1 https://archive.starfleet.example.com:8443/
openssl s_client -connect 127.0.0.1:8443 -servername archive.starfleet.example.com </dev/null 2>/dev/null | openssl x509 -noout -subject
```

The response body is `{"service":"archive"}`. The certificate subject names `archive.starfleet.example.com`. No secret in `istio-system` holds that certificate: the gateway never decrypted the connection, and the `archive` pod terminated TLS itself. List the gateway's secrets and check that none of them is `archive`:

```sh
istioctl proxy-config secret deploy/istio-ingressgateway -n istio-system
```

### See what a wrong route does

The route for a passthrough host must be a `tls:` match. To see the difference, change the `archive` `VirtualService` so that its route is an `http:` rule, and send the request again. The request no longer reaches `archive`. The gateway has no HTTP route for a host it cannot decrypt, so the connection never gets the archive's answer. Restore the `tls:` match, apply the file again, and the request works.

You now know that `MUTUAL` needs a `ca.crt` in the secret and rejects clients without a valid certificate, and that `PASSTHROUGH` forwards encrypted traffic by SNI to a backend that terminates TLS, with a `tls:` match in the `VirtualService`. The next step is to find these faults when they are not yours.

## Common pitfalls

> [!WARNING]
> - **A `MUTUAL` secret without `ca.crt`.** `kubectl create secret tls` makes only `tls.crt` and `tls.key`. Make a generic secret with all three keys.
> - **A client certificate that the CA in `ca.crt` did not sign.** The handshake fails even though the client sends a certificate.
> - **An `http:` route for a `PASSTHROUGH` host.** The gateway never decrypts, so it cannot read paths or headers. Use `tls:` with `sniHosts`.
> - **`protocol: HTTPS` on a passthrough server.** Use `protocol: TLS`, because the gateway forwards bytes and does not speak HTTP on that server.
> - **Expecting a certificate in `istio-system` for a passthrough host.** The backend holds the certificate. The gateway has none.

## Your mission: Fix A Secret In The Wrong Namespace And A Passthrough Mismatch Lab

You can now read a `Gateway` `tls` block, and you know where each certificate must be. The mission gives you a gateway where one HTTPS host and one passthrough host both fail, and asks you to find both causes and prove the fix with real requests.

Pause the playground, then start the lab and submit it:

```sh
astrona stop ats-014-playground-060-04
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-060/module-04/labs/lab-02
astrona submit -c sections/section-060/module-04/labs/lab-02
```

When you are done, remove the lab and start the playground again:

```sh
astrona destroy ats-014-lab-060-04-02
astrona start ats-014-playground-060-04
```
