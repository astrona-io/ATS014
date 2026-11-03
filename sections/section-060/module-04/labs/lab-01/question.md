---
estimated_duration: 30m
---

# Question

Solve this question on: `terminal`

The `probe` Service in the `starfleet` namespace must be reachable from outside the cluster over HTTPS, through Istio's ingress gateway, and plain HTTP requests must be redirected to HTTPS.

The `starfleet` namespace holds:

* `probe-v1` and `probe-v2`: an HTTP echo server behind one `probe` Service on port `8000`. It answers any path, for example `/get`.
* `shuttle`: a client pod with `curl`.

Istio 1.30.5 is installed in `istio-system`, with its ingress gateway: the Deployment and Service `istio-ingressgateway`, with pods labelled `istio: ingressgateway`. There is **no `Gateway`, no `VirtualService` and no TLS secret** yet.

A self-signed certificate and its private key for `probe.example.com` are on your machine: **`/tmp/probe-example.crt`** and **`/tmp/probe-example.key`**.

Reach the gateway with port forwards:

```bash
kubectl -n istio-system port-forward svc/istio-ingressgateway 8080:80  >/dev/null 2>&1 &
kubectl -n istio-system port-forward svc/istio-ingressgateway 8443:443 >/dev/null 2>&1 &
```

Do the following:

1.  Create a TLS secret named **`probe-tls`** from the certificate and the key, in the namespace where the gateway can read it.
2.  Create a `Gateway` named **`probe-gateway`** in the `starfleet` namespace for the gateway pods labelled `istio: ingressgateway`, with two servers:
    *   port **443**, protocol `HTTPS`, host **`probe.example.com`**, `tls.mode` **`SIMPLE`** and `credentialName` **`probe-tls`**
    *   port **80**, protocol `HTTP`, host **`probe.example.com`**, with HTTPS redirect switched on
3.  Create a `VirtualService` named **`probe`** in `starfleet`, for host `probe.example.com`, bound to `probe-gateway`, that routes every request to the `probe` Service on port `8000`.

**What the grader checks**

4.  The secret `probe-tls` exists in `istio-system` and has the type `kubernetes.io/tls`.
5.  The gateway proxy holds `kubernetes://probe-tls` with the status `ACTIVE`, and has a listener on port `443`.
6.  `GET /get` over **HTTPS** on port 8443, with the name `probe.example.com` as SNI, returns **200**.
7.  The certificate that the gateway serves for `probe.example.com` is the one from `/tmp/probe-example.crt`.
8.  `GET /get` over **plain HTTP** with `Host: probe.example.com` returns **301**, and the redirect address starts with `https://probe.example.com`.
