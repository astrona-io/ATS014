# Solution Walkthrough

You build one edge in four steps: a secret, a `Gateway`, a `DestinationRule` and a `VirtualService`. Items 1 to 4 create the objects. Items 5 to 10 are what the grader reads back, so each of them is checked after the step that fixes it.

---

## Start

Start the two port forwards from the task, and check that nothing exists yet:

```sh
kubectl -n istio-system port-forward svc/istio-ingressgateway 8080:80  >/dev/null 2>&1 &
kubectl -n istio-system port-forward svc/istio-ingressgateway 8443:443 >/dev/null 2>&1 &
kubectl get gateway,virtualservice,destinationrule -n starfleet
kubectl get secret -n istio-system
```

The first command lists no resources. The second shows no secret named `starfleet-tls`.

---

## Task item 1: The TLS Secret

> **Task item 1:** Create a TLS secret named **`starfleet-tls`** from the certificate and the key, in the namespace where the gateway can read it.

The gateway pod runs in `istio-system` and reads secrets only from its own namespace. Create the secret there with the `tls` type:

```sh
kubectl -n istio-system create secret tls starfleet-tls \
  --key=/tmp/starfleet-edge.key --cert=/tmp/starfleet-edge.crt
```

Check the type:

```sh
kubectl -n istio-system get secret starfleet-tls -o jsonpath='{.type}{"\n"}'
```

The type is `kubernetes.io/tls`.

---

## Task item 2: The Gateway

> **Task item 2:** Create a `Gateway` named **`starfleet-gateway`** in `starfleet` ... with an HTTPS server on port 443 and a port 80 server that redirects to HTTPS.

Save the object to a file, then apply it:

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
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - starfleet.example.com
    tls:
      httpsRedirect: true
```

```sh
kubectl apply -f gateway-starfleet-gateway.yaml
```

Check that the gateway proxy loaded the secret:

```sh
istioctl proxy-config secret deploy/istio-ingressgateway -n istio-system
```

The row `kubernetes://starfleet-tls` has the status `ACTIVE`. Wait a few seconds if it is not listed yet.

---

## Task item 3: The DestinationRule

> **Task item 3:** Create a `DestinationRule` named **`probe`** in `starfleet` with the subsets **`v1`** and **`v2`**, selecting the pods by the label `version`.

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: probe
  namespace: starfleet
spec:
  host: probe
  subsets:
  - name: v1
    labels:
      version: v1
  - name: v2
    labels:
      version: v2
```

```sh
kubectl apply -f destinationrule-probe.yaml
```

---

## Task item 4: The VirtualService

> **Task item 4:** Create a `VirtualService` named **`starfleet`** in `starfleet`, bound to `starfleet-gateway`, for host `starfleet.example.com`, with these routes and no others.

The beta rule comes before the general `/hostname` rule. Istio uses the first rule that matches, so the order decides which rule answers a request with the header:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: starfleet
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
        prefix: /hostname
      headers:
        x-channel:
          exact: beta
    route:
    - destination:
        host: probe
        subset: v2
        port:
          number: 8000
  - match:
    - uri:
        prefix: /hostname
    route:
    - destination:
        host: probe
        subset: v1
        port:
          number: 8000
```

```sh
kubectl apply -f virtualservice-starfleet.yaml
```

---

## Task items 5 And 6: The Secret And HTTPS

> **Task item 5:** The secret `starfleet-tls` is in `istio-system` with the type `kubernetes.io/tls`, and the gateway proxy holds `kubernetes://starfleet-tls` with the status `ACTIVE`.

Items 1 and 2 already satisfy this. Confirm it again:

```sh
istioctl proxy-config secret deploy/istio-ingressgateway -n istio-system
```

> **Task item 6:** `GET /productpage` over **HTTPS** on port 8443, with the name `starfleet.example.com` as SNI, returns **200**.

```sh
curl -sk -o /dev/null -w '%{http_code}\n' --resolve starfleet.example.com:8443:127.0.0.1 https://starfleet.example.com:8443/productpage
```

The request returns `200`. Istio can need a few seconds to push the new routes, so repeat the command if it returns `404`.

---

## Task item 7: The Served Certificate

> **Task item 7:** The certificate that the gateway serves for `starfleet.example.com` is the one from `/tmp/starfleet-edge.crt`.

Compare the two fingerprints:

```sh
openssl s_client -connect 127.0.0.1:8443 -servername starfleet.example.com </dev/null 2>/dev/null | openssl x509 -noout -fingerprint -sha256
openssl x509 -in /tmp/starfleet-edge.crt -noout -fingerprint -sha256
```

The two fingerprints are the same.

---

## Task items 8 And 9: Header Routing And The 404

> **Task item 8:** Over HTTPS, `GET /hostname` with the header `x-channel: beta` is answered by a `probe-v2` pod. Five requests without the header are all answered by a `probe-v1` pod.

```sh
curl -sk --resolve starfleet.example.com:8443:127.0.0.1 -H 'x-channel: beta' https://starfleet.example.com:8443/hostname
for i in 1 2 3 4 5; do curl -sk --resolve starfleet.example.com:8443:127.0.0.1 https://starfleet.example.com:8443/hostname; done
```

The first request returns the name of a `probe-v2` pod. The five others return the name of a `probe-v1` pod.

> **Task item 9:** Over HTTPS, `GET /status/200` returns **404** from the gateway: no route exists for it.

```sh
curl -sk -o /dev/null -w '%{http_code}\n' --resolve starfleet.example.com:8443:127.0.0.1 https://starfleet.example.com:8443/status/200
```

The request returns `404`, because no rule matches the prefix `/status`.

---

## Task item 10: The HTTP Redirect

> **Task item 10:** `GET /productpage` over **plain HTTP** with `Host: starfleet.example.com` returns **301**, and the redirect address starts with `https://starfleet.example.com`.

Do not use `-L`. The redirect address has no port, so curl would go to port 443 on your machine:

```sh
curl -s -o /dev/null -w '%{http_code} %{redirect_url}\n' -H 'Host: starfleet.example.com' http://127.0.0.1:8080/productpage
```

The status is `301`, and the redirect address starts with `https://starfleet.example.com`.

---

## Submit

```sh
astrona submit -c sections/section-060/capstone/labs/lab-02
```

## Mistakes That Fail The Grader

- **Items 1 and 5:** the secret is created in `starfleet`. The gateway reads `istio-system` only, and the secret stays `WARMING` or is missing.
- **Items 1 and 5:** the secret is created with `kubectl create secret generic`. The type must be `kubernetes.io/tls`.
- **Items 2 and 7:** `credentialName` differs from the secret name, or a new certificate is generated instead of the one in `/tmp/starfleet-edge.crt`.
- **Item 3:** the `DestinationRule` `host` is not `probe`, or a subset selects the wrong label.
- **Items 4 and 8:** the general `/hostname` rule is placed before the beta rule. The beta rule never matches.
- **Item 4:** the `VirtualService` has no `gateways` entry, so it does not apply to the ingress gateway.
- **Item 9:** an extra catch-all route is added. Requests for other paths must get `404`.
- **Item 10:** the port 80 server has no `httpsRedirect: true`, so the gateway routes the request instead of redirecting it.
