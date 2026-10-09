# TLS And The Feature Ceiling

Astronaut, two things are left. First, TLS on an `Ingress`, where one rule about namespaces causes most of the failures. Second, an honest list of what the `Ingress` API cannot do, which is why the other two APIs exist.

## TLS on an `Ingress`

An `Ingress` turns on HTTPS with one extra block, `spec.tls`. It lists the host names to protect and the secret that holds the certificate:

```yaml
spec:
  ingressClassName: istio
  tls:
  - hosts:
    - starfleet.example.com
    secretName: starfleet-credential
```

`secretName` names an ordinary Kubernetes TLS secret (type `kubernetes.io/tls`, with the keys `tls.crt` and `tls.key`).

### The namespace rule

> **The secret must be in the gateway's namespace, `istio-system`, not in the namespace of the `Ingress`.**

That is the opposite of almost every other Kubernetes object, and the reason is *who reads it*. The gate pod loads the certificate, and the gate reads secrets from its own namespace. Think of the certificate as the gate's secret handshake: it has to be stored on the gate's own planet, not on the planet where your ships live. The `Ingress` lives with your ships; the gate that needs the key lives somewhere else.

The failure is quiet and lopsided:

- Plain HTTP keeps working.
- HTTPS gets no answer: curl prints `000`.
- `kubectl` shows nothing wrong. There is no event and no warning on the `Ingress`.

HTTP fine, HTTPS dead, no error: that is the signature. Check which namespace the secret is in before anything else.

<!-- astrona:playground:renew -->

### Make a certificate

Create a self-signed certificate for `starfleet.example.com`. This writes two files, `starfleet.key` and `starfleet.crt`, in your current folder:

```sh
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout starfleet.key -out starfleet.crt \
  -subj "/CN=starfleet.example.com/O=starfleet"
```

### Put the secret on the wrong planet

Create the secret where it feels natural, next to the `Ingress` in `starfleet`:

```sh
kubectl create secret tls starfleet-credential -n starfleet --key=starfleet.key --cert=starfleet.crt
```

```text
secret/starfleet-credential created
```

Now add the `tls` block to your `Ingress`. Save this as `ingress-starfleet.yaml`, replacing the old file:

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

Then send one signal over HTTPS and one over plain HTTP:

```sh
curl -sk -o /dev/null -w 'HTTPS: %{http_code}\n' --resolve starfleet.example.com:8443:127.0.0.1 https://starfleet.example.com:8443/productpage
curl -s -o /dev/null -w 'HTTP:  %{http_code}\n' -H "Host: starfleet.example.com" http://$GATEWAY_URL/productpage
```

```text
HTTPS: 000
HTTP:  200
```

The HTTPS curl needs two extra flags. `-k` accepts the self-signed certificate. `--resolve` points the name `starfleet.example.com` at your machine, so curl sends the right name in the TLS handshake (the name the gate uses to pick a certificate). A `Host` header alone is not enough for HTTPS.

### See why the handshake fails

Ask the gate which certificates it holds, and ask mission control what went wrong:

```sh
istioctl proxy-config secret deploy/istio-ingressgateway -n istio-system
kubectl logs -n istio-system deploy/istiod | grep starfleet-credential | grep warn
```

You should see (trimmed):

```text
RESOURCE NAME                         TYPE           STATUS      VALID CERT     ...
kubernetes://starfleet-credential                    WARMING     false
default                               Cert Chain     ACTIVE      true           ...
ROOTCA                                CA             ACTIVE      true           ...
2026-10-08T22:13:56.626589Z	warn	ads	failed to fetch key and certificate for kubernetes://starfleet-credential: secret istio-system/starfleet-credential not found
```

The gate is still waiting for `starfleet-credential` (`WARMING`, no valid certificate), so it cannot finish a handshake. Mission control says exactly where it looked: `istio-system/starfleet-credential`.

### Move the secret to the gate's planet

Create the same secret in `istio-system`:

```sh
kubectl create secret tls starfleet-credential -n istio-system --key=starfleet.key --cert=starfleet.crt
```

```text
secret/starfleet-credential created
```

Then send the HTTPS signal again and look at the gate's certificates:

```sh
curl -sk -o /dev/null -w 'HTTPS: %{http_code}\n' --resolve starfleet.example.com:8443:127.0.0.1 https://starfleet.example.com:8443/productpage
istioctl proxy-config secret deploy/istio-ingressgateway -n istio-system
```

You should see (trimmed):

```text
HTTPS: 200
RESOURCE NAME                         TYPE           STATUS     VALID CERT     ...
default                               Cert Chain     ACTIVE     true           ...
kubernetes://starfleet-credential     CA             ACTIVE     true           ...
ROOTCA                                CA             ACTIVE     true           ...
```

`ACTIVE` and `true`, and the signal gets `200`. Nothing in the `Ingress` changed, only where the secret lives. The copy in `starfleet` does nothing at all, so remove it:

```sh
kubectl delete secret starfleet-credential -n starfleet
```

### Read the gate's listeners

The gate now has a listener on port `443`, built from your `Ingress`:

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

`SNI: starfleet.example.com` (Server Name Indication, the host name the caller sends in the TLS handshake) is how the gate picks this listener's certificate. That is the name `--resolve` made curl send.

## What the API cannot express

This matters more in the exam than any field name. The `Ingress` API routes by host and path, and that is about all:

| Istio feature | `Ingress` equivalent |
| --- | --- |
| Weighted routing and canary releases | **none**: there is no `weight` field |
| Mirroring traffic | **none** |
| Matching on headers, query parameters or methods | **none**: host and path only |
| Timeouts and retries | **none** |
| Fault injection | **none** |
| Subsets, load balancing, connection pools, outlier detection | **none**: those live in a `DestinationRule` |
| Choosing which gateway serves it | **none**: always the mesh-wide default gate |
| Explicit rule order | **none**: the most specific path wins, details are up to the controller |
| Routing rules that reach across namespaces | **none** |

Other controllers have filled these gaps with their own annotations, a different set for each controller. That works, and it makes an `Ingress` file useless on any other controller. Ending that split is exactly why the Kubernetes Gateway API was created. Istio does not add a large set of annotations: if you need more than host and path, use a different API.

### Check it yourself

Look at what a path's backend can hold:

```sh
kubectl explain ingress.spec.rules.http.paths.backend
```

You should see (trimmed to the fields):

```text
FIELDS:
  resource	<TypedLocalObjectReference>
  service	<IngressServiceBackend>
```

One Service or one other object, with no `weight` and no list. There is no way to split signals between two backends.

## Choosing between the three APIs

All three can open the same gate to the same flagship. Pick by what you need:

| Situation | Use |
| --- | --- |
| Existing `Ingress` files you want served without a rewrite | **`Ingress`** with `ingressClassName: istio` |
| You need weights, header matching, retries, mirroring, faults or subsets | Istio's **`Gateway` with a `VirtualService`** |
| New work, and you want files that work on any implementation | The **Gateway API** |
| A platform team owns the gate, and ship teams own their routes | The **Gateway API**: that split is built into its objects |

`Ingress` support exists so that a migration does not have to start with a rewrite. It is a docking adapter for older ships. Use it knowing where it stops.

## Common pitfalls

> [!WARNING]
> - **Creating the TLS secret next to the `Ingress`.** The gate reads secrets from `istio-system`. HTTP keeps working, and HTTPS never comes up.
> - **Testing HTTPS with only a `Host` header.** The gate picks its certificate from the name in the TLS handshake. Use `--resolve` so curl sends the real name.
> - **Taking a working HTTPS test as proof after you moved a secret away.** A running gate keeps the certificate it already loaded. It breaks only when the gate restarts, so the mistake shows up later, not now.
> - **Expecting Istio features from an `Ingress`.** No weights, no header matching, no retries, no timeouts, no faults. Those need a `VirtualService`.
> - **Trusting the `ADDRESS` column.** On a cluster with no load balancer it stays empty, healthy or not.

> *An `Ingress` TLS secret lives in the gateway's namespace, because the gateway pod is what has to read it.*

## Your mission: Expose A Service With A Kubernetes Ingress

You can now claim an `Ingress`, route hosts and paths with the right `pathType`, and add TLS with the secret on the right planet. Now prove all three in one graded mission.

The mission runs in its own training solar system, so first pause your playground. Nothing in it is lost:

```sh
astrona stop ats-014-playground-060-02
```

Then start the mission:

```sh
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-060/module-02/labs/lab-01
```

Read the task in [`question.md`](./labs/lab-01/question.md) and solve it on your own first. When you think you are done, send it for grading:

```sh
astrona submit -c sections/section-060/module-02/labs/lab-01
```

When the mission is done, remove it and wake your playground up again:

```sh
astrona destroy ats-014-lab-060-02
astrona start ats-014-playground-060-02
```
