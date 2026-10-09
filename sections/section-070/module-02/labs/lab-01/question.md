# Question

Solve this question on: `terminal`

A partner service outside the mesh only accepts TLS (Transport Layer Security) connections, but the client application keeps sending plain HTTP. Make the client's sidecar proxy originate TLS, that is, open the TLS connection itself on the way out.

The cluster has two namespaces:

* `tlsorig-demo`: sidecar injection on. It holds a `tester` client pod with `curl`.
* `outside-mesh`: sidecar injection **off**. It holds a bare pod `secure-api` with **no Service**, so it is not in the mesh's service registry.

`secure-api` listens **only on port 8443, with TLS**. Plain HTTP to that port fails. It answers every request with the scheme it received, `scheme=https`, so there is no guessing whether TLS origination worked.

Its address is in **`/tmp/secure-ip`**, and its self-signed certificate is at `/tmp/secure-api-ca.crt`. This lab needs no internet access.

`tester` must call it over **plain `http://` on port 8080**, and the `tester` pod's sidecar proxy must do the TLS.

1.  Create a `ServiceEntry` named **`secure-api`** in `tlsorig-demo` for host **`secure.example.com`**, with the endpoint's address in `spec.addresses`, `location: MESH_EXTERNAL`, `resolution: STATIC`, and an `endpoints` entry for that address.
2.  Declare **two** ports on it:
    *   **8080**, name `http`, protocol **`HTTP`**: where the application's plain request arrives
    *   **8443**, name `https`, protocol **`HTTPS`**: where the encrypted request goes
3.  Create a `VirtualService` named **`secure-api`** for `secure.example.com` that matches **port 8080** and routes to **port 8443** on the same host.
4.  Create a `DestinationRule` named **`secure-api`** for `secure.example.com` with `trafficPolicy.portLevelSettings` for **port 8443** only, setting `tls.mode` to **`SIMPLE`** and `tls.sni` to **`secure.example.com`**.
5.  The endpoint uses a **self-signed** certificate, so add `insecureSkipVerify: true` to that `tls` block. In production you would set `caCertificates` instead. Here it is a lab shortcut: without it, the proxy rejects the certificate and the grader's request fails.
6.  Do **not** change the application's behaviour: `tester` calls `http://<secure-ip>:8080/`, never `https://`.

**What the grader checks**

7.  `GET http://<secure-ip>:8080/` from `tester` returns **200**.
8.  The response body contains **`scheme=https`**. The endpoint received a TLS connection, which is only possible if the sidecar proxy originated it.
9.  The `ServiceEntry` declares both ports with the required protocols, the address, `MESH_EXTERNAL`, `STATIC` and the endpoint.
10. The `VirtualService` matches port 8080 and routes to `secure.example.com` on port 8443.
11. The `DestinationRule`'s `tls` block is under **`portLevelSettings` for port 8443**, not at the top level of `trafficPolicy`. A top-level `tls` also applies to port 8080 and breaks the plain side.
12. `sni` is set to `secure.example.com`.
13. The `tester` proxy's cluster for `secure.example.com` has a TLS transport socket.
14. No Service exists in `outside-mesh`.
