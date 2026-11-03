# Terminate HTTPS With tls.mode SIMPLE And credentialName

A `Gateway` that only opens port 80 sends every request over the network in clear text. Anyone on the path can read the headers and the body. To protect the traffic, the ingress gateway must accept HTTPS, and for that it needs a certificate and a private key. This part shows the one `Gateway` block that does it, where the certificate must be stored, and how to prove that the gateway serves it.

## The `tls` block of a `Gateway` server

A `Gateway` lists `servers`. Each server opens one port for a list of hosts. To make a server speak HTTPS, set its protocol to `HTTPS` and add a `tls` block:

```yaml
servers:
- port:
    number: 443
    name: https
    protocol: HTTPS
  hosts:
  - starfleet.example.com
  tls:
    mode: SIMPLE
    credentialName: starfleet-tls
```

`mode: SIMPLE` means ordinary TLS, as a browser uses it: the gateway proves its identity with a certificate, and the client does not. The gateway terminates TLS. That means it decrypts the connection itself, and then it routes the plain HTTP request inside, like on a port 80 server. Because the gateway decrypts the request, a `VirtualService` can still match paths and headers.

`credentialName` names a Kubernetes secret that holds the certificate and the private key. You do not mount that secret into the gateway pod. `istiod` reads it and sends it to the gateway over SDS (Secret Discovery Service), the part of xDS that carries certificates and keys. xDS is the set of protocols `istiod` uses to push configuration to proxies while they run.

The secret must have the type `kubernetes.io/tls`, with the keys `tls.crt` and `tls.key`. It must be in the same namespace as the gateway pod, which is `istio-system` here, not in the namespace of the `Gateway` object. The `Gateway` lives in `starfleet`, but the proxy that needs the key runs in `istio-system`.

## Terminate HTTPS for one host

The steps below give the gateway a certificate and a route for `starfleet.example.com`. The playground forwards local port `8443` to port `443` of the gateway.

<!-- astrona:playground:renew -->

### Create the certificate and the secret

First create a self-signed certificate for `starfleet.example.com`. A self-signed certificate is signed with its own key, so no certificate authority (CA) vouches for it. That is fine for a test. The command writes `starfleet.key` and `starfleet.crt` in your current folder:

```sh
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout starfleet.key -out starfleet.crt \
  -subj "/CN=starfleet.example.com/O=starfleet"
```

Now create the secret in the gateway's namespace with `kubectl create secret tls`. This command checks the files and sets the type `kubernetes.io/tls` for you:

```sh
kubectl create secret tls starfleet-tls -n istio-system --key=starfleet.key --cert=starfleet.crt
```

### Open port 443 and route the requests

Save this as `gateway-starfleet-gateway.yaml`. The `selector` matches the label of the gateway pod, `istio: ingressgateway`:

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
      number: 443
      name: https
      protocol: HTTPS
    hosts:
    - starfleet.example.com
    tls:
      mode: SIMPLE
      credentialName: starfleet-tls
```

Apply it:

```sh
kubectl apply -f gateway-starfleet-gateway.yaml
```

A `Gateway` opens the port but routes nothing. Save this as `virtualservice-bridge.yaml`. It sends `/productpage` to `bridge` and `/anything` to `probe`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: bridge
  namespace: starfleet
spec:
  hosts:
  - starfleet.example.com
  gateways:
  - starfleet-gateway
  http:
  - match:
    - uri:
        prefix: /productpage
    route:
    - destination:
        host: bridge
        port:
          number: 9080
  - match:
    - uri:
        prefix: /anything
    route:
    - destination:
        host: probe
        port:
          number: 8000
```

Apply it:

```sh
kubectl apply -f virtualservice-bridge.yaml
```

### Send an HTTPS request

Send one request through the forwarded port:

```sh
curl -sk -o /dev/null -w '%{http_code}\n' --resolve starfleet.example.com:8443:127.0.0.1 https://starfleet.example.com:8443/productpage
```

The command prints `200`. It needs two extra flags. `-k` tells curl to accept the self-signed certificate. `--resolve` points the name `starfleet.example.com` at `127.0.0.1` for this command, so curl sends that name in the TLS handshake. The gateway picks its certificate from that name, called the SNI (Server Name Indication), so a `Host` header alone is not enough for HTTPS.

Port 80 is a different case. This `Gateway` has no server for port 80, so the gateway has no listener there. Run `curl -s -o /dev/null -w '%{http_code}\n' -H "Host: starfleet.example.com" http://localhost:8080/productpage`. Curl prints `000`, because the connection is refused.

### Prove which certificate the gateway serves

A `200` shows that HTTPS works, but not which certificate the gateway used. Ask for the certificate itself with `openssl s_client`, and print its subject:

```sh
openssl s_client -connect 127.0.0.1:8443 -servername starfleet.example.com </dev/null 2>/dev/null | openssl x509 -noout -subject
```

The subject line names `starfleet.example.com`. That is the certificate you created. Then ask the gateway proxy which secrets it holds, and which listeners it has:

```sh
istioctl proxy-config secret deploy/istio-ingressgateway -n istio-system
istioctl proxy-config listeners deploy/istio-ingressgateway -n istio-system
```

The secret list has a row `kubernetes://starfleet-tls`, with the status `ACTIVE`. The prefix `kubernetes://` marks a secret that came from a Kubernetes `Secret`, and `ACTIVE` means the proxy loaded it. The listener list has a row for port `443`, which `istiod` built from the `Gateway`.

> [!TIP]
> Treat `proxy-config secret` as the first check after any TLS change. A status of `ACTIVE` means the gateway holds the certificate. A status of `WARMING` means the proxy asked for it and `istiod` could not find it.

You now know that `tls.mode: SIMPLE` makes the gateway terminate HTTPS, that `credentialName` points at a `kubernetes.io/tls` secret in the gateway's namespace, and how to prove the result with three commands. The open question is what happens to clients that still use plain HTTP, and what happens with a second host that needs its own certificate.

## Common pitfalls

> [!WARNING]
> - **Creating the secret in the namespace of the `Gateway`.** The gateway pod reads secrets from its own namespace, `istio-system`. A secret in `starfleet` is never loaded.
> - **Testing HTTPS with only a `Host` header.** The gateway picks its certificate from the SNI in the handshake. Use `--resolve`, so curl sends the real name.
> - **Leaving out `-k` with a self-signed certificate.** Curl refuses the connection because no trusted CA signed the certificate. That is a client check, not a gateway fault.
> - **Using `protocol: HTTP` on port 443.** The `tls` block needs `protocol: HTTPS`. Istio does not accept the combination.
> - **Reading a `200` as proof of the certificate.** Use `openssl s_client` to see which certificate the gateway really sent.
