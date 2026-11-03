---
estimated_duration: 30m
---

# Question

Solve this question on: `terminal`

The `starfleet` namespace is reachable from outside the cluster over HTTPS through Istio's ingress gateway. Two hosts are configured on one `Gateway`, and both fail. Kubernetes and Istio accepted every object, and `kubectl` reports no error.

The `starfleet` namespace holds:

* `probe-v1` and `probe-v2`: an HTTP echo server behind one `probe` Service on port `8000`. It answers any path under `/anything`.
* `archive`: an nginx server that terminates TLS itself on port `8443`, behind the Service `archive` on port `443`. It has its own certificate for `archive.starfleet.example.com` and no sidecar proxy. It answers every request with `{"service":"archive"}`.
* `shuttle`: a client pod with `curl`.

Istio 1.30.5 is installed in `istio-system`, with its ingress gateway: the Deployment and Service `istio-ingressgateway`, with pods labelled `istio: ingressgateway`.

These objects already exist:

* A `Gateway` named `starfleet-gateway` in `starfleet`, with two servers on port 443. The server for `starfleet.example.com` terminates TLS (`SIMPLE`) with `credentialName: starfleet-tls`. The server for `archive.starfleet.example.com` is `PASSTHROUGH`. **Both servers are meant to stay as they are.**
* A `VirtualService` named `probe` for `starfleet.example.com`, and a `VirtualService` named `archive` for `archive.starfleet.example.com`.
* A secret named `starfleet-tls`, created from the certificate and key at **`/tmp/starfleet-example.crt`** and **`/tmp/starfleet-example.key`**.

Reach the gateway with a port forward:

```bash
kubectl -n istio-system port-forward svc/istio-ingressgateway 8443:443 >/dev/null 2>&1 &
```

The lab saves its starting state in the files `gateway-starfleet-gateway.yaml`, `virtualservice-probe.yaml` and `virtualservice-archive.yaml` in its `resources` folder. `astrona res` lists them.

Fix the problems so that:

1.  `GET /anything/dock` over **HTTPS** on port 8443, with the name `starfleet.example.com` as SNI, returns **200**.
2.  The certificate that the gateway serves for `starfleet.example.com` is the one from `/tmp/starfleet-example.crt`, and the gateway proxy holds `kubernetes://starfleet-tls` with the status `ACTIVE`.
3.  A request over HTTPS on port 8443 with the name `archive.starfleet.example.com` as SNI reaches the `archive` and returns its body, `{"service":"archive"}`.
4.  The certificate presented for `archive.starfleet.example.com` is the `archive`'s own certificate, the one in the secret `archive-tls` in `starfleet`. The gateway must not decrypt this traffic.
5.  The `Gateway` keeps its two servers: `starfleet.example.com` with `tls.mode: SIMPLE`, and `archive.starfleet.example.com` with `tls.mode: PASSTHROUGH` and `protocol: TLS`.
6.  The Deployments and Services in `starfleet` stay unchanged.

The grader sends live requests through the gateway, so the fixes have to work, not only exist.
