---
estimated_duration: 45m
---

# Question

Solve this question on: `terminal`

The `starfleet` namespace must be served to the outside over HTTPS through Istio's ingress gateway. The edge combines TLS with routing: the web frontend, and the echo `probe` in two versions, chosen by a request header.

The `starfleet` namespace holds:

* `bridge`: the web frontend, a Service on port `9080`. Its page is `/productpage`.
* `cargo`, `scout` v1/v2/v3 and `navcom`: the backends that `bridge` calls.
* `probe-v1` and `probe-v2`: an HTTP echo server behind one `probe` Service on port `8000`. The path `/hostname` returns the name of the pod that answered. The pods have the label `version: v1` or `version: v2`.
* `shuttle`: a client pod with `curl`.

Istio 1.30.5 is installed in `istio-system`, with its ingress gateway: the Deployment and Service `istio-ingressgateway`, with pods labelled `istio: ingressgateway`. There is **no `Gateway`, `VirtualService`, `DestinationRule` or TLS secret** yet.

A self-signed certificate and its private key for `starfleet.example.com` are on your machine: **`/tmp/starfleet-edge.crt`** and **`/tmp/starfleet-edge.key`**.

Reach the gateway with port forwards:

```bash
kubectl -n istio-system port-forward svc/istio-ingressgateway 8080:80  >/dev/null 2>&1 &
kubectl -n istio-system port-forward svc/istio-ingressgateway 8443:443 >/dev/null 2>&1 &
```

Build the edge for the host **`starfleet.example.com`**:

1.  Create a TLS secret named **`starfleet-tls`** from the certificate and the key, in the namespace where the gateway can read it.
2.  Create a `Gateway` named **`starfleet-gateway`** in `starfleet` for the gateway pods labelled `istio: ingressgateway`, with an HTTPS server on port 443 (`tls.mode: SIMPLE`, `credentialName: starfleet-tls`) and a port 80 server that redirects to HTTPS. Both servers are for the host `starfleet.example.com`.
3.  Create a `DestinationRule` named **`probe`** in `starfleet` with the subsets **`v1`** and **`v2`**, selecting the pods by the label `version`.
4.  Create a `VirtualService` named **`starfleet`** in `starfleet`, bound to `starfleet-gateway`, for host `starfleet.example.com`, with these routes and no others:
    *   paths that start with **`/productpage`** go to the `bridge` Service on port `9080`
    *   paths that start with **`/hostname`** and carry the header **`x-channel: beta`** go to the `probe` subset **`v2`**
    *   all other paths that start with **`/hostname`** go to the `probe` subset **`v1`**

**What the grader checks**

5.  The secret `starfleet-tls` is in `istio-system` with the type `kubernetes.io/tls`, and the gateway proxy holds `kubernetes://starfleet-tls` with the status `ACTIVE`.
6.  `GET /productpage` over **HTTPS** on port 8443, with the name `starfleet.example.com` as SNI, returns **200**.
7.  The certificate that the gateway serves for `starfleet.example.com` is the one from `/tmp/starfleet-edge.crt`.
8.  Over HTTPS, `GET /hostname` with the header `x-channel: beta` is answered by a `probe-v2` pod. Five requests without the header are all answered by a `probe-v1` pod.
9.  Over HTTPS, `GET /status/200` returns **404** from the gateway: no route exists for it.
10. `GET /productpage` over **plain HTTP** with `Host: starfleet.example.com` returns **301**, and the redirect address starts with `https://starfleet.example.com`.
