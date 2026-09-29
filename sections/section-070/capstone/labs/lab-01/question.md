# Question

Solve this question on: `terminal`

The mesh is **deny-by-default** (`outboundTrafficPolicy.mode: REGISTRY_ONLY`). Three endpoints exist and none is registered, so all three are refused.

**`integrations`** (injected)
* `tester` — client pod with `curl`
* `legacy-vm` — an **uninjected** pod running as ServiceAccount **`legacy-sa`**, answering HTTP on **8080**. This is **your** machine, standing in for a VM. Address in `/tmp/vm-ip`.

**`outside-mesh`** (not injected, no Services)
* `partner-api` — a **TLS-only** endpoint on **8443**. Plaintext to it fails. It answers with the scheme it was reached over. Address in `/tmp/partner-ip`.
* `blocked-api` — HTTP on 8080. Must **stay** refused. Address in `/tmp/blocked-ip`.

Deliver all three outcomes.

**A — The partner API, reached over plain HTTP**

1.  A [`ServiceEntry`](https://istio.io/latest/docs/reference/config/networking/service-entry/) named **`partner`** in `integrations` for host **`partner.example.com`**, with the partner address in `spec.addresses`, `location` **`MESH_EXTERNAL`**, `resolution` **`STATIC`**, an `endpoints` entry for that address, and **`exportTo: ["."]`**.
2.  Two ports on it: **8080** name `http` protocol **`HTTP`**, and **8443** name `https` protocol **`HTTPS`**.
3.  A [`VirtualService`](https://istio.io/latest/docs/reference/config/networking/virtual-service/) named **`partner`** matching **port 8080** and routing to **port 8443** on the same host.
4.  A [`DestinationRule`](https://istio.io/latest/docs/reference/config/networking/destination-rule/) named **`partner`** with `trafficPolicy.portLevelSettings` for **port 8443** only, `tls.mode` **`SIMPLE`**, `tls.sni` **`partner.example.com`**, and `insecureSkipVerify: true` (the certificate is self-signed).

**B — Your machine, as a mesh member**

5.  A [`WorkloadEntry`](https://istio.io/latest/docs/reference/config/networking/workload-entry/) named **`legacy-vm`** in `integrations` with the machine's `address`, the label **`app: legacy`**, and `serviceAccount` **`legacy-sa`**.
6.  A `ServiceEntry` named **`legacy`** in `integrations` for host **`legacy.integrations.svc`**, `location` **`MESH_INTERNAL`**, `resolution` **`STATIC`**, port **8080** name `http` protocol `HTTP`, and a `workloadSelector` matching `app: legacy`.

**C — Leave the third one alone**

7.  Do not register `blocked-api`, and do not relax the mesh to `ALLOW_ANY`.

**What the grader checks**

8.  The mesh is still `REGISTRY_ONLY`.
9.  `GET http://<partner-ip>:8080/` from `tester` returns **200** and the body contains **`scheme=https`** — a plain HTTP call reached a TLS-only endpoint, so the sidecar originated the handshake.
10. The partner `DestinationRule`'s `tls` block is under `portLevelSettings` for 8443, not at the top level.
11. `GET http://legacy.integrations.svc:8080/get` returns **200** — the machine is reachable by name.
12. The legacy `ServiceEntry` is `MESH_INTERNAL`, and the `WorkloadEntry` carries `serviceAccount: legacy-sa`.
13. `GET http://<blocked-ip>:8080/get` does **not** return 200.

---

---

## Reference

The official documentation for everything this task touches — open these rather than trying to recall field names:

- [VirtualService API](https://istio.io/latest/docs/reference/config/networking/virtual-service/) — the whole object: `hosts`, `gateways`, and every field an `http` rule can carry
- [DestinationRule API](https://istio.io/latest/docs/reference/config/networking/destination-rule/) — `host`, `subsets`, and the `trafficPolicy` block
- [ServiceEntry API](https://istio.io/latest/docs/reference/config/networking/service-entry/) — `hosts`, `ports`, `location`, `resolution` and `endpoints`
- [WorkloadEntry API](https://istio.io/latest/docs/reference/config/networking/workload-entry/) — `address`, `labels` and `serviceAccount`
- [Subsets and traffic policy](https://istio.io/latest/docs/reference/config/networking/destination-rule/#Subset) — how a subset name maps to pod labels
- [HTTPMatchRequest API](https://istio.io/latest/docs/reference/config/networking/virtual-service/#HTTPMatchRequest) — every match key: `headers`, `uri`, `queryParams`, `method`, `withoutHeaders`
- [TrafficPolicy portLevelSettings](https://istio.io/latest/docs/reference/config/networking/destination-rule/#TrafficPolicy-PortTrafficPolicy) — attaching policy to one port instead of the whole host
- [ClientTLSSettings API](https://istio.io/latest/docs/reference/config/networking/destination-rule/#ClientTLSSettings) — `mode`, `credentialName` and `sni` for origination
- [Configuration scoping](https://istio.io/latest/docs/ops/configuration/mesh/configuration-scoping/) — how `exportTo` and `Sidecar` together decide what a proxy sees
- [MeshConfig outboundTrafficPolicy](https://istio.io/latest/docs/reference/config/istio.mesh.v1alpha1/#MeshConfig-OutboundTrafficPolicy) — `ALLOW_ANY` versus `REGISTRY_ONLY`
- [Protocol selection](https://istio.io/latest/docs/ops/configuration/traffic-management/protocol-selection/) — how a port's name or `appProtocol` decides what Istio does with it
- [Debugging Envoy and istiod](https://istio.io/latest/docs/ops/diagnostic-tools/proxy-cmd/) — `proxy-status`, `proxy-config` and `x describe` in full
