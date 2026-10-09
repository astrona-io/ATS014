# Add TLS To An Ingress

A Kubernetes `Ingress` is an object that describes how requests from outside the cluster reach a Service inside it. Plain HTTP (Hypertext Transfer Protocol) is not enough for real traffic: clients expect HTTPS, which is HTTP inside a TLS (Transport Layer Security) connection. TLS encrypts the connection and lets the client check the server's certificate. An `Ingress` turns on HTTPS with one small block, but one rule about namespaces causes most of the failures. This part shows that rule, the failure it causes, and how to prove the fix.

## The `tls` block and the namespace rule

An `Ingress` turns on HTTPS with the block `spec.tls`. It lists the host names to protect and the secret that holds the certificate and the private key:

```yaml
spec:
  ingressClassName: istio
  tls:
  - hosts:
    - starfleet.example.com
    secretName: starfleet-credential
```

`secretName` names an ordinary Kubernetes TLS secret: a secret of type `kubernetes.io/tls` with the keys `tls.crt` and `tls.key`.

The secret must be in the gateway's namespace, `istio-system`, not in the namespace of the `Ingress`. That is the opposite of most other Kubernetes objects, and the reason is which component reads the secret. The ingress gateway, the Envoy proxy at the edge of the mesh that serves every `Ingress`, terminates TLS. That means it decrypts the HTTPS connection, so it must load the certificate. The gateway reads TLS secrets only from its own namespace. The `Ingress` lives next to your application, but the component that needs the key runs in `istio-system`.

When the secret is in the wrong namespace, the failure is quiet and one-sided. Plain HTTP keeps working. HTTPS gets no response, so curl prints `000`. And `kubectl` shows nothing wrong: there is no event and no warning on the `Ingress`. HTTP works, HTTPS fails, and there is no error: when you see that pattern, check the secret's namespace first.

## See the failure, then fix it

The steps below create a certificate, put the secret in the wrong namespace on purpose, and then move it. They need the `istio` `IngressClass` (with `spec.controller: istio.io/ingress-controller`) in the cluster, and `GATEWAY_URL=localhost:8080` set in your shell. The playground forwards local port `8080` to port `80` of the gateway, and local port `8443` to port `443`.

<!-- astrona:playground:renew -->

### Create the certificate and a secret in the wrong namespace

First create a self-signed certificate for `starfleet.example.com`. This command writes two files, `starfleet.key` and `starfleet.crt`, in your current folder:

```sh
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout starfleet.key -out starfleet.crt \
  -subj "/CN=starfleet.example.com/O=starfleet"
```

Now create the secret where it seems natural, next to the `Ingress` in the `starfleet` namespace:

```sh
kubectl create secret tls starfleet-credential -n starfleet --key=starfleet.key --cert=starfleet.crt
```

```text
secret/starfleet-credential created
```

Next, add the `tls` block to the `Ingress`. Save this as `ingress-starfleet.yaml`, replacing the old file:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: starfleet
  namespace: starfleet
spec:
  ingressClassName: istio
  tls:
  - hosts:
    - starfleet.example.com
    secretName: starfleet-credential
  rules:
  - host: starfleet.example.com
    http:
      paths:
      - path: /productpage
        pathType: Prefix
        backend:
          service:
            name: bridge
            port:
              number: 9080
      - path: /anything/dock
        pathType: Prefix
        backend:
          service:
            name: probe
            port:
              number: 8000
      - path: /status/200
        pathType: Exact
        backend:
          service:
            name: probe
            port:
              number: 8000
```

Apply it:

```sh
kubectl apply -f ingress-starfleet.yaml
```

Then send one request over HTTPS and one over plain HTTP:

```sh
curl -sk -o /dev/null -w 'HTTPS: %{http_code}\n' --resolve starfleet.example.com:8443:127.0.0.1 https://starfleet.example.com:8443/productpage
curl -s -o /dev/null -w 'HTTP:  %{http_code}\n' -H "Host: starfleet.example.com" http://$GATEWAY_URL/productpage
```

```text
HTTPS: 000
HTTP:  200
```

The HTTPS command needs two extra flags. `-k` tells curl to accept the self-signed certificate. `--resolve` points the name `starfleet.example.com` at your machine, so curl sends that name in the TLS handshake. The gateway uses that name to pick a certificate, so a `Host` header alone is not enough for HTTPS.

### Find out why the handshake fails

Two tools show the cause. `istioctl proxy-config secret` lists the certificates the gateway holds, and the `istiod` log shows what Istio's control plane tried to do:

```sh
istioctl proxy-config secret deploy/istio-ingressgateway -n istio-system
kubectl logs -n istio-system deploy/istiod | grep starfleet-credential | grep warn
```

You should see this (shortened):

```text
RESOURCE NAME                         TYPE           STATUS      VALID CERT     ...
kubernetes://starfleet-credential                    WARMING     false
default                               Cert Chain     ACTIVE      true           ...
ROOTCA                                CA             ACTIVE      true           ...
2026-10-08T22:13:56.626589Z	warn	ads	failed to fetch key and certificate for kubernetes://starfleet-credential: secret istio-system/starfleet-credential not found
```

The gateway is still waiting for `starfleet-credential`: its status is `WARMING` and it has no valid certificate, so it cannot finish a TLS handshake. The `istiod` log line says exactly where Istio looked: `istio-system/starfleet-credential`.

### Move the secret to the gateway's namespace

Create the same secret in `istio-system`:

```sh
kubectl create secret tls starfleet-credential -n istio-system --key=starfleet.key --cert=starfleet.crt
```

```text
secret/starfleet-credential created
```

Then send the HTTPS request again and list the gateway's certificates:

```sh
curl -sk -o /dev/null -w 'HTTPS: %{http_code}\n' --resolve starfleet.example.com:8443:127.0.0.1 https://starfleet.example.com:8443/productpage
istioctl proxy-config secret deploy/istio-ingressgateway -n istio-system
```

You should see this (shortened):

```text
HTTPS: 200
RESOURCE NAME                         TYPE           STATUS     VALID CERT     ...
default                               Cert Chain     ACTIVE     true           ...
kubernetes://starfleet-credential     CA             ACTIVE     true           ...
ROOTCA                                CA             ACTIVE     true           ...
```

The secret is now `ACTIVE` with a valid certificate, and the request gets `200`. Nothing in the `Ingress` changed; only the secret's namespace changed. The copy in `starfleet` does nothing at all, so remove it:

```sh
kubectl delete secret starfleet-credential -n starfleet
```

### Read the gateway's listeners

A listener is the part of Envoy's configuration that accepts connections on one address and port. `istiod` built a listener on port `443` from your `Ingress`:

```sh
istioctl proxy-config listeners deploy/istio-ingressgateway -n istio-system
```

```text
ADDRESSES PORT  MATCH                      DESTINATION
0.0.0.0   80    ALL                        Route: http.80
0.0.0.0   443   SNI: starfleet.example.com Route: https.443.https-443-ingress-starfleet-starfleet-0.starfleet-istio-autogenerated-k8s-ingress-starfleet.istio-system
0.0.0.0   15021 ALL                        Inline Route: /healthz/ready*
0.0.0.0   15090 ALL                        Inline Route: /stats/prometheus*
```

SNI (Server Name Indication) is the host name the client sends in the TLS handshake. The match `SNI: starfleet.example.com` is how the gateway picks the certificate for this listener. It is the name that `--resolve` made curl send.

You now know that `spec.tls` turns on HTTPS, that its secret must be in `istio-system` because the gateway loads it, and how to prove the result with `proxy-config secret` and `proxy-config listeners`. With host, path and TLS covered, the open question is what an `Ingress` cannot do at all.

## Common pitfalls

> [!WARNING]
> - **Creating the TLS secret next to the `Ingress`.** The gateway reads secrets from `istio-system`. HTTP keeps working, and HTTPS never comes up.
> - **Testing HTTPS with only a `Host` header.** The gateway picks its certificate from the name in the TLS handshake. Use `--resolve` so curl sends the real name.
> - **Trusting a working HTTPS test after you moved a secret away.** A running gateway keeps the certificate it already loaded. It breaks only when the gateway restarts, so the mistake shows up later, not now.
> - **Trusting the `ADDRESS` column.** On a cluster with no load balancer it stays empty, whether HTTPS works or not.
