# Solution Walkthrough

The task has three things to create: a secret, a `Gateway` and a `VirtualService`. The ingress gateway is the Envoy proxy that accepts traffic from outside the cluster. It terminates HTTPS with a certificate that `istiod`, Istio's control plane, reads from a secret and sends to it. Each section below ends with a check. Items 4 to 8 are what the grader checks, and the checks in items 1 to 3 prepare them.

---

## Start: Confirm The Starting State

The task says there is no `Gateway`, no `VirtualService` and no TLS secret. Confirm it, and look at the files you received:

```sh
kubectl get gateway,virtualservice -A
kubectl get secret -n istio-system
ls -l /tmp/probe-example.crt /tmp/probe-example.key
```

The first command finds no `Gateway` and no `VirtualService`. The second shows no secret named `probe-tls`. The third lists the two files.

---

## Task item 1: Create The TLS Secret

> **Task item 1:** Create a TLS secret named **`probe-tls`** from the certificate and the key, in the namespace where the gateway can read it.

The gateway pod runs in `istio-system`, and it reads secrets only from its own namespace. Create the secret there with `kubectl create secret tls`, which sets the type `kubernetes.io/tls` and the keys `tls.crt` and `tls.key`:

```sh
kubectl -n istio-system create secret tls probe-tls \
  --key=/tmp/probe-example.key --cert=/tmp/probe-example.crt
```

Check the secret and its type:

```sh
kubectl -n istio-system get secret probe-tls
```

The `TYPE` column shows `kubernetes.io/tls`.

---

## Task items 2 And 3: The Gateway And The VirtualService

> **Task item 2:** Create a `Gateway` named **`probe-gateway`** in the `starfleet` namespace ... with two servers: port 443 ... and port 80 ...

> **Task item 3:** Create a `VirtualService` named **`probe`** in `starfleet`, for host `probe.example.com`, bound to `probe-gateway`, that routes every request to the `probe` Service on port `8000`.

These two items belong together: the `Gateway` opens the ports, and the `VirtualService` routes the requests that arrive on them. The `selector` of the `Gateway` is the label of the gateway pod, `istio: ingressgateway`. The HTTPS server uses `protocol: HTTPS` with `tls.mode: SIMPLE` and `credentialName: probe-tls`. The port 80 server uses a `tls` block with only `httpsRedirect: true`.

Save this as `gateway-probe-gateway.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: Gateway
metadata:
  name: probe-gateway
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
    - probe.example.com
    tls:
      mode: SIMPLE
      credentialName: probe-tls
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - probe.example.com
    tls:
      httpsRedirect: true
```

Apply it:

```sh
kubectl apply -f gateway-probe-gateway.yaml
```

Save this as `virtualservice-probe.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: probe
  namespace: starfleet
spec:
  hosts:
  - probe.example.com
  gateways:
  - probe-gateway
  http:
  - route:
    - destination:
        host: probe
        port:
          number: 8000
```

Apply it:

```sh
kubectl apply -f virtualservice-probe.yaml
```

Then check that `istioctl analyze` has no complaint about the namespace:

```sh
istioctl analyze -n starfleet
```

---

## Task items 4 And 5: What The Gateway Holds

> **Task item 4:** The secret `probe-tls` exists in `istio-system` and has the type `kubernetes.io/tls`.

> **Task item 5:** The gateway proxy holds `kubernetes://probe-tls` with the status `ACTIVE`, and has a listener on port `443`.

Item 4 is what you checked after item 1. For item 5, ask the gateway proxy:

```sh
istioctl proxy-config secret deploy/istio-ingressgateway -n istio-system
istioctl proxy-config listeners deploy/istio-ingressgateway -n istio-system
```

The secret list has a row `kubernetes://probe-tls` with the status `ACTIVE`. If the status is `WARMING`, `istiod` cannot find the secret: check its name, its namespace and `credentialName`. The listener list has a row for port `443`.

---

## Task items 6 And 7: HTTPS And The Certificate

> **Task item 6:** `GET /get` over **HTTPS** on port 8443, with the name `probe.example.com` as SNI, returns **200**.

> **Task item 7:** The certificate that the gateway serves for `probe.example.com` is the one from `/tmp/probe-example.crt`.

Start the port forwards from the task, then send the request. `--resolve` makes curl send `probe.example.com` as the SNI, and `-k` accepts the self-signed certificate:

```sh
curl -sk -o /dev/null -w '%{http_code}\n' --resolve probe.example.com:8443:127.0.0.1 https://probe.example.com:8443/get
```

The status code is `200`. For item 7, compare the fingerprint of the certificate that the gateway sends with the fingerprint of your file:

```sh
openssl s_client -connect 127.0.0.1:8443 -servername probe.example.com </dev/null 2>/dev/null | openssl x509 -noout -fingerprint -sha256
openssl x509 -in /tmp/probe-example.crt -noout -fingerprint -sha256
```

The two fingerprints are the same.

---

## Task item 8: The Redirect

> **Task item 8:** `GET /get` over **plain HTTP** with `Host: probe.example.com` returns **301**, and the redirect address starts with `https://probe.example.com`.

Send a plain HTTP request through the forwarded port 8080 and print the status code and the redirect address:

```sh
curl -s -o /dev/null -w '%{http_code} %{redirect_url}\n' -H "Host: probe.example.com" http://localhost:8080/get
```

The status code is `301`, and the address starts with `https://probe.example.com/get`. The gateway answered the redirect itself, so no route was read.

---

## Submit

```sh
astrona submit -c sections/section-060/module-04/labs/lab-01
```

## Mistakes That Fail The Grader

- **Item 1 and 4:** the secret is in `starfleet`. The gateway reads secrets from `istio-system` only.
- **Item 1 and 4:** the secret is a generic secret, so its type is `Opaque`. Use `kubectl create secret tls`.
- **Item 5:** `credentialName` differs from the secret name. The secret stays `WARMING` or never appears.
- **Item 5 and 6:** the `selector` of the `Gateway` does not match the label `istio: ingressgateway`, so the gateway has no listener on `443`.
- **Item 6:** the `VirtualService` is not bound with `gateways: [probe-gateway]`, or its host is not `probe.example.com`.
- **Item 7:** a new certificate was created instead of using `/tmp/probe-example.crt`.
- **Item 8:** `httpsRedirect: true` is missing, or the port 80 server lists another host.
