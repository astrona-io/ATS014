# Question

Solve this question on: `terminal`

* `tlsorig-demo` — injected, holds a `tester` client pod with `curl`
* `outside-mesh` — **not** injected, holds a bare pod `secure-api` with **no Service**, so it is not in the mesh registry.

`secure-api` listens **only on port 8443, with TLS**. Plaintext to that port fails. It answers every request with the scheme it was actually reached over — `scheme=https` — so there is no guessing whether origination worked.

Its address is in **`/tmp/secure-ip`** and its self-signed certificate is at `/tmp/secure-api-ca.crt`. This lab needs no internet access.

`tester` must be able to call it over **plain `http://` on port 8080** and have the sidecar do the TLS.

1.  Create a [`ServiceEntry`](https://istio.io/latest/docs/reference/config/networking/service-entry/) named **`secure-api`** in `tlsorig-demo` for host **`secure.example.com`**, with the endpoint's address in `spec.addresses`, `location: MESH_EXTERNAL`, `resolution: STATIC`, and an `endpoints` entry for that address.
2.  Declare **two** ports on it:
    *   **8080**, name `http`, protocol **`HTTP`** — where the application arrives
    *   **8443**, name `https`, protocol **`HTTPS`** — where the traffic is going
3.  Create a [`VirtualService`](https://istio.io/latest/docs/reference/config/networking/virtual-service/) named **`secure-api`** for `secure.example.com` that matches **port 8080** and routes to **port 8443** on the same host.
4.  Create a [`DestinationRule`](https://istio.io/latest/docs/reference/config/networking/destination-rule/) named **`secure-api`** for `secure.example.com` with `trafficPolicy.portLevelSettings` for **port 8443** only, setting `tls.mode` to **`SIMPLE`** and `tls.sni` to **`secure.example.com`**.
5.  The endpoint uses a **self-signed** certificate, so add `insecureSkipVerify: true` to that `tls` block. In production you would supply `caCertificates` instead — this is a lab shortcut and the grader expects it here.
6.  Do **not** change the application's behaviour: `tester` calls `http://<secure-ip>:8080/`, never `https://`.

**What the grader checks**

7.  `GET http://<secure-ip>:8080/` from `tester` returns **200**.
8.  The response body contains **`scheme=https`** — the endpoint saw a TLS connection, which is only possible if the sidecar originated it.
9.  The `ServiceEntry` declares both ports with the required protocols.
10. The `DestinationRule`'s `tls` block is under **`portLevelSettings` for port 8443**, not at the top level of `trafficPolicy`. A top-level `tls` also applies to port 8080 and breaks the plaintext side.
11. `sni` is set to `secure.example.com`.
12. The `tester` proxy's cluster for `secure.example.com` on port 8443 has a TLS transport socket.

---

---

## Reference

The official documentation for everything this task touches — open these rather than trying to recall field names:

- [VirtualService API](https://istio.io/latest/docs/reference/config/networking/virtual-service/) — the whole object: `hosts`, `gateways`, and every field an `http` rule can carry
- [DestinationRule API](https://istio.io/latest/docs/reference/config/networking/destination-rule/) — `host`, `subsets`, and the `trafficPolicy` block
- [ServiceEntry API](https://istio.io/latest/docs/reference/config/networking/service-entry/) — `hosts`, `ports`, `location`, `resolution` and `endpoints`
- [Subsets and traffic policy](https://istio.io/latest/docs/reference/config/networking/destination-rule/#Subset) — how a subset name maps to pod labels
- [HTTPMatchRequest API](https://istio.io/latest/docs/reference/config/networking/virtual-service/#HTTPMatchRequest) — every match key: `headers`, `uri`, `queryParams`, `method`, `withoutHeaders`
- [TrafficPolicy portLevelSettings](https://istio.io/latest/docs/reference/config/networking/destination-rule/#TrafficPolicy-PortTrafficPolicy) — attaching policy to one port instead of the whole host
- [ClientTLSSettings API](https://istio.io/latest/docs/reference/config/networking/destination-rule/#ClientTLSSettings) — `mode`, `credentialName` and `sni` for origination
- [Protocol selection](https://istio.io/latest/docs/ops/configuration/traffic-management/protocol-selection/) — how a port's name or `appProtocol` decides what Istio does with it
- [Debugging Envoy and istiod](https://istio.io/latest/docs/ops/diagnostic-tools/proxy-cmd/) — `proxy-status`, `proxy-config` and `x describe` in full
