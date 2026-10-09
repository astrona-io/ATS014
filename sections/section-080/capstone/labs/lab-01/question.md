# Question

Solve this question on: `terminal`

Two partner servers outside the mesh must be reached through **one** egress gateway, an Envoy proxy at the edge of the mesh that outgoing traffic passes through. One partner speaks plain HTTP and only one client may be routed to it through the egress gateway. The other partner only accepts TLS (Transport Layer Security), so the egress gateway must start the TLS connection. Your cluster has:

* `edge-egress` (sidecar injection on), with two clients:
  * `tester`, whose pods carry `app: tester` **and `egress-allowed: "true"`**
  * `other-client`, whose pods carry only `app: other-client`
* `outside-mesh` (sidecar injection off, no Services), with two servers:
  * `plain-api`: plain HTTP on **8080**. Its IP address is in `/tmp/plain-ip`.
  * `secure-api`: **TLS only** on **8443**, so a plain text request fails. It reports the scheme it was reached over. Its IP address is in `/tmp/secure-ip`.
* `istio-egressgateway`, running in `istio-system` and carrying no traffic.

Create the following objects, all in `edge-egress`.

**Partner A: plain HTTP, routed through the egress gateway for one workload only**

1.  A `ServiceEntry` named **`plain`** for the host **`plain.partner.example`**: the `plain-api` address in `spec.addresses`, port **8080** named `http` with protocol `HTTP`, `MESH_EXTERNAL`, `STATIC`, and an `endpoints` entry for that address.
2.  A `Gateway` named **`egress-gateway`** that selects `istio: egressgateway`, with **two servers**: port **8080** with protocol `HTTP` for `plain.partner.example`, and port **8081** with protocol `HTTP` for `secure.partner.example`. A separate listener port per host keeps the two routes apart.
3.  A `DestinationRule` named **`egressgateway-subsets`** for `istio-egressgateway.istio-system.svc.cluster.local` with **two** subsets, **`plain`** and **`secure`**, both without labels.
4.  A `VirtualService` named **`plain-through-egress`** for `plain.partner.example`, with the top-level gateways `mesh` and `egress-gateway`, and two rules:
    *   Rule 1: matches port 8080 and **`sourceLabels: {egress-allowed: "true"}`**, with no `gateways` in the match, and routes to the egress gateway Service, subset `plain`, port **8080**. Match on the **port and `sourceLabels` only**; do **not** add `gateways: [mesh]` here. On Istio 1.30.5, combining `gateways: [mesh]` with `sourceLabels` makes Istio ignore the label condition, and every sidecar proxy gets the route to the egress gateway. The rule still cannot match on the egress gateway itself, because the egress gateway pod does not carry that label.
    *   Rule 2: `gateways: [egress-gateway]`, port 8080, routes to `plain.partner.example` port **8080**.

**Partner B: TLS started at the egress gateway**

5.  A `ServiceEntry` named **`secure`** for the host **`secure.partner.example`**: the `secure-api` address in `spec.addresses`, **two ports** (**8081** named `http` with protocol `HTTP`, and **8443** named `https` with protocol `HTTPS`), `MESH_EXTERNAL`, `STATIC`, and an `endpoints` entry for that address.
6.  A `VirtualService` named **`secure-through-egress`** for `secure.partner.example`, with the top-level gateways `mesh` and `egress-gateway`, and two rules:
    *   Rule 1: `gateways: [mesh]`, port **8081**, routes to the egress gateway Service, subset `secure`, port **8081**.
    *   Rule 2: `gateways: [egress-gateway]`, port **8081**, routes to `secure.partner.example` port **8443**.
7.  A `DestinationRule` named **`originate-tls-for-secure`** for the host **`secure.partner.example`**, with `portLevelSettings` for port **8443**: `tls.mode` **`SIMPLE`**, `tls.sni` **`secure.partner.example`**, and `insecureSkipVerify: true`. Limit it with **`exportTo: [istio-system]`**. By default a `DestinationRule` for an external host is visible to the whole mesh, so without `exportTo` every sidecar proxy also gets the TLS settings for the host, and the grader checks that the client's sidecar proxy does *not* have them.

**What the grader checks**

8.  From `tester`: `GET http://plain.partner.example:8080/get` returns **200**, and the egress gateway logs it. The mesh resolves both host names from their `ServiceEntry`, and the egress gateway's listeners match on the host name.
9.  From `tester`: `GET http://secure.partner.example:8081/` returns **200** with the body `scheme=https`, and the egress gateway logs it with an upstream on **8443**.
10. From `other-client`: the plain call still returns **200**, but the egress gateway logs **no** line for it. `sourceLabels` limits which workloads get the route through the egress gateway; it does not block the others.
11. The **egress gateway** has a TLS `transportSocket` in its cluster for `secure.partner.example`; the **`tester` sidecar proxy** does not.
12. The TLS `DestinationRule` names `secure.partner.example` and keeps its `tls` block under `portLevelSettings`, not at the top level.
13. Both hosts are carried by the same egress gateway Deployment, and no Service exists in `outside-mesh`.
