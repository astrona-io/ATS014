# Question

Solve this question on: `terminal`

* `edge-egress` (injected) — two clients:
  * `tester`, whose pods carry `app: tester` **and `egress-allowed: "true"`**
  * `other-client`, whose pods carry only `app: other-client`
* `outside-mesh` (not injected, no Services) — two endpoints:
  * `plain-api` — plain HTTP on **8080**. Address in `/tmp/plain-ip`.
  * `secure-api` — **TLS only** on **8443**; plaintext fails. Reports the scheme it was reached over. Address in `/tmp/secure-ip`.
* `istio-egressgateway` runs in `istio-system` and carries no traffic.

Route **both** partners through the **one** egress gateway.

**Partner A — plain HTTP, restricted to one workload**

1.  A [`ServiceEntry`](https://istio.io/latest/docs/reference/config/networking/service-entry/) named **`plain`** for host **`plain.partner.example`** — the plain address, port **8080** name `http` protocol `HTTP`, `MESH_EXTERNAL`, `STATIC`, with an `endpoints` entry.
2.  A [`Gateway`](https://istio.io/latest/docs/reference/config/networking/gateway/) named **`egress-gateway`** in `edge-egress`, selecting `istio: egressgateway`, with **two servers**: port **8080** protocol `HTTP` for `plain.partner.example`, and port **8081** protocol `HTTP` for `secure.partner.example`. Using a separate listener port per host keeps the two chains distinguishable.
3.  A [`DestinationRule`](https://istio.io/latest/docs/reference/config/networking/destination-rule/) named **`egressgateway-subsets`** for `istio-egressgateway.istio-system.svc.cluster.local` with **two** subsets, **`plain`** and **`secure`**, neither carrying labels.
4.  A [`VirtualService`](https://istio.io/latest/docs/reference/config/networking/virtual-service/) named **`plain-through-egress`** for `plain.partner.example`, gateways `mesh` and `egress-gateway`, with two stages:
    *   Stage 1 — port 8080 and **`sourceLabels: {egress-allowed: "true"}`**, with no `gateways` in the match → gateway Service, subset `plain`, port **8080**. Match on the **port and `sourceLabels` only** — do **not** add `gateways: [mesh]` here. On Istio 1.30.5 combining it with `sourceLabels` makes the label predicate be ignored and every sidecar gets the diverting route. The rule still cannot fire on the gateway itself, because the gateway pod does not carry that label.
    *   Stage 2 — `gateways: [egress-gateway]`, port 8080 → `plain.partner.example` port **8080**

**Partner B — TLS originated at the gateway**

5.  A `ServiceEntry` named **`secure`** for host **`secure.partner.example`** — the secure address, **two ports**: **8081** name `http` protocol `HTTP` and **8443** name `https` protocol `HTTPS`, `MESH_EXTERNAL`, `STATIC`, with an `endpoints` entry.
6.  A `VirtualService` named **`secure-through-egress`** for `secure.partner.example`, gateways `mesh` and `egress-gateway`, with two stages:
    *   Stage 1 — `gateways: [mesh]`, port **8081** → gateway Service, subset `secure`, port **8081**
    *   Stage 2 — `gateways: [egress-gateway]`, port **8081** → `secure.partner.example` port **8443**
7.  A `DestinationRule` named **`originate-tls-for-secure`** for host **`secure.partner.example`**, `portLevelSettings` for port **8443**, `tls.mode` **`SIMPLE`**, `tls.sni` **`secure.partner.example`**, `insecureSkipVerify: true`. Scope it with **`exportTo: [istio-system]`**. A `DestinationRule` for an external host is visible mesh-wide by default, so without that every sidecar originates TLS for the host too — and the grader checks that the client sidecar does *not*.

**What the grader checks**

8.  From `tester`: `GET http://plain.partner.example:8080/get` returns **200** and the gateway logs it. The mesh resolves both hostnames from their `ServiceEntry`, and the hostname is what the gateway's listeners match on.
9.  From `tester`: `GET http://secure.partner.example:8081/` returns **200** with body `scheme=https`, and the gateway logs it with an upstream on **8443**.
10. From `other-client`: the plain call still returns **200** but produces **no** gateway log line — `sourceLabels` narrows the route, not the permission.
11. The **gateway** proxy has a TLS `transportSocket` for `secure.partner.example`; the **tester sidecar** does not.
12. Both hosts are carried by the same gateway deployment.

---

---

## Reference

The official documentation for everything this task touches — open these rather than trying to recall field names:

- [VirtualService API](https://istio.io/latest/docs/reference/config/networking/virtual-service/) — the whole object: `hosts`, `gateways`, and every field an `http` rule can carry
- [DestinationRule API](https://istio.io/latest/docs/reference/config/networking/destination-rule/) — `host`, `subsets`, and the `trafficPolicy` block
- [Gateway API](https://istio.io/latest/docs/reference/config/networking/gateway/) — `selector`, `servers`, `port`, `hosts` and the `tls` block
- [ServiceEntry API](https://istio.io/latest/docs/reference/config/networking/service-entry/) — `hosts`, `ports`, `location`, `resolution` and `endpoints`
- [Subsets and traffic policy](https://istio.io/latest/docs/reference/config/networking/destination-rule/#Subset) — how a subset name maps to pod labels
- [HTTPMatchRequest API](https://istio.io/latest/docs/reference/config/networking/virtual-service/#HTTPMatchRequest) — every match key: `headers`, `uri`, `queryParams`, `method`, `withoutHeaders`
- [TrafficPolicy portLevelSettings](https://istio.io/latest/docs/reference/config/networking/destination-rule/#TrafficPolicy-PortTrafficPolicy) — attaching policy to one port instead of the whole host
- [ClientTLSSettings API](https://istio.io/latest/docs/reference/config/networking/destination-rule/#ClientTLSSettings) — `mode`, `credentialName` and `sni` for origination
- [Configuration scoping](https://istio.io/latest/docs/ops/configuration/mesh/configuration-scoping/) — how `exportTo` and `Sidecar` together decide what a proxy sees
- [Protocol selection](https://istio.io/latest/docs/ops/configuration/traffic-management/protocol-selection/) — how a port's name or `appProtocol` decides what Istio does with it
- [Debugging Envoy and istiod](https://istio.io/latest/docs/ops/diagnostic-tools/proxy-cmd/) — `proxy-status`, `proxy-config` and `x describe` in full
