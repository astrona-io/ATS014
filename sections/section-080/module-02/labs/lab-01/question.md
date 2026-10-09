# Question

Solve this question on: `terminal`

A partner server outside the mesh only accepts TLS (Transport Layer Security), but the client in the mesh only sends plain `http://`. The egress gateway, an Envoy proxy at the edge of the mesh that outgoing traffic passes through, must start the TLS connection for every request. Your cluster has:

* `egwtls-demo` (sidecar injection on): a `tester` client pod with `curl`.
* `outside-mesh` (sidecar injection off): `partner-api`, a bare pod with **no Service**. It listens **only on port 8443 with TLS**, so a plain text request to it fails. It answers with the scheme it was reached over, for example `scheme=https`. Its IP address is in **`/tmp/partner-ip`**.
* `istio-egressgateway`, running in `istio-system` and carrying no traffic.

There is no Istio configuration yet, and this lab needs no internet access.

The `tester` pod must reach the partner server with plain **`http://` on port 8080**, and the **egress gateway** must do the TLS handshake. Create these five objects, all in `egwtls-demo`:

1.  A `ServiceEntry` named **`partner`** for the host **`partner.example.com`**, with the partner's IP address in `spec.addresses`, `location` **`MESH_EXTERNAL`**, `resolution` **`STATIC`**, an `endpoints` entry for that address, and **two ports**: **8080** named `http` with protocol **`HTTP`**, and **8443** named `https` with protocol **`HTTPS`**.
2.  A `Gateway` named **`egress-gateway`** that selects **`istio: egressgateway`** and opens port **8080** with protocol **`HTTP`** for the host **`partner.example.com`**.
3.  A `DestinationRule` named **`egressgateway-for-partner`** for the host `istio-egressgateway.istio-system.svc.cluster.local`, with one subset named **`partner`** and no labels.
4.  A `VirtualService` named **`partner-through-egress`** for `partner.example.com` that lists both **`mesh`** and **`egress-gateway`** in its top-level `gateways`, with two `http` rules:
    *   **Rule 1**: `gateways: [mesh]`, port **8080**, routes to the egress gateway Service, subset `partner`, port **8080**.
    *   **Rule 2**: `gateways: [egress-gateway]`, port **8080**, routes to `partner.example.com` port **8443**.
5.  A `DestinationRule` named **`originate-tls-for-partner`** for the host **`partner.example.com`** (the **external** host, not the egress gateway). Put the TLS settings under `trafficPolicy.portLevelSettings` for port **8443**: `tls.mode` **`SIMPLE`**, `tls.sni` **`partner.example.com`**, and `insecureSkipVerify: true` (the partner's certificate is self-signed). Limit it with **`exportTo: [istio-system]`**. By default a `DestinationRule` for an external host is visible to the whole mesh, so without `exportTo` every sidecar proxy also gets the TLS settings for the host, and the grader checks that the client's sidecar proxy does *not* have them.

**What the grader checks**

6.  `GET http://partner.example.com:8080/` from `tester` returns **200**, and the body contains **`scheme=https`**. The mesh resolves that name from the `ServiceEntry`; the egress gateway's route matches on the host name, not on an IP address.
7.  The **egress gateway's own access log** gains a line for the request, with the upstream on port **8443**.
8.  The **egress gateway's** cluster for `partner.example.com` has a TLS `transportSocket`, and the **`tester` sidecar proxy's** cluster does **not**. A `DestinationRule` is applied by the proxy that calls the host.
9.  Rule 2 routes to port **8443**, while the `Gateway` listener stays on **8080**.
10. The TLS `DestinationRule` names `partner.example.com`, and its `tls` block is under `portLevelSettings`, not at the top level.
11. No Service exists in `outside-mesh`, and both the `tester` Deployment and the `partner-api` pod are running.
