# Question

Solve this question on: `terminal`

* `egwtls-demo` (injected) — a `tester` client pod with `curl`
* `outside-mesh` (not injected) — `partner-api`, a bare pod with **no Service** listening **only on 8443 with TLS**. Plaintext to it fails. It answers with the scheme it was reached over. Address in **`/tmp/partner-ip`**.
* `istio-egressgateway` is running in `istio-system` and carrying no traffic.

There is no Istio configuration. This lab needs no internet access.

`tester` must reach the partner over plain **`http://` on port 8080**, with the **egress gateway** doing the TLS handshake.

1.  A [`ServiceEntry`](https://istio.io/latest/docs/reference/config/networking/service-entry/) named **`partner`** in `egwtls-demo` for host **`partner.example.com`**, with the partner address in `spec.addresses`, `location` **`MESH_EXTERNAL`**, `resolution` **`STATIC`**, an `endpoints` entry for that address, and **two ports**: **8080** name `http` protocol **`HTTP`**, and **8443** name `https` protocol **`HTTPS`**.
2.  A [`Gateway`](https://istio.io/latest/docs/reference/config/networking/gateway/) named **`egress-gateway`** in `egwtls-demo`, selecting **`istio: egressgateway`**, opening port **8080** protocol **`HTTP`** for host **`partner.example.com`**.
3.  A [`DestinationRule`](https://istio.io/latest/docs/reference/config/networking/destination-rule/) named **`egressgateway-for-partner`** for host `istio-egressgateway.istio-system.svc.cluster.local` with one subset named **`partner`** and no labels.
4.  A [`VirtualService`](https://istio.io/latest/docs/reference/config/networking/virtual-service/) named **`partner-through-egress`** for `partner.example.com`, listing both **`mesh`** and **`egress-gateway`** in its top-level `gateways`, with two `http` rules:
    *   **Stage 1** — `gateways: [mesh]`, port **8080** → the egress gateway Service, subset `partner`, port **8080**
    *   **Stage 2** — `gateways: [egress-gateway]`, port **8080** → `partner.example.com` port **8443**
5.  A `DestinationRule` named **`originate-tls-for-partner`** for host **`partner.example.com`** — the **external** host, not the gateway — with `trafficPolicy.portLevelSettings` for port **8443**, `tls.mode` **`SIMPLE`**, `tls.sni` **`partner.example.com`**, and `insecureSkipVerify: true` (the certificate is self-signed). Scope it with **`exportTo: [istio-system]`**. A `DestinationRule` for an external host is visible mesh-wide by default, so without that every sidecar originates TLS for the host too — and the grader checks that the client sidecar does *not*.

**What the grader checks**

6.  `GET http://partner.example.com:8080/` from `tester` returns **200** and the body contains **`scheme=https`**. The mesh resolves that name from the `ServiceEntry`; the gateway's route matches on the hostname, not on an IP.
7.  The **gateway's own access log** gains a line for the request, with the upstream on port **8443**.
8.  The **gateway** proxy's cluster for `partner.example.com` has a TLS `transportSocket`, and the **tester sidecar's** does **not**. The policy is applied by the proxy that makes the call.
9.  Stage 2 routes to port **8443** while the `Gateway` listener stays on **8080**.
10. The origination `DestinationRule` targets `partner.example.com`, and its `tls` block is under `portLevelSettings`, not at the top level.

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
