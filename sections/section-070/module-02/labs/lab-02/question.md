# Question

Solve this question on: `terminal`

The team in `starfleet` reports a problem. The `shuttle` must reach the `vault` in `outpost`, and every request it sends fails.

The cluster has two namespaces:

* `starfleet`: sidecar injection on. It holds `shuttle`, a client pod with `curl`. Send your test requests from here.
* `outpost`: **no** sidecar injection. It holds a bare pod `vault` with **no Service**, so the vault is not in the mesh's service registry on its own.

The `vault` listens **only on port `8443`, with TLS** (Transport Layer Security). A plain HTTP request to that port gets `400`. It answers every request with the scheme it received, for example `vault: scheme=https`, so you can see whether TLS was added. Get its address with:

```sh
kubectl get pod vault -n outpost -o jsonpath='{.status.podIP}'
```

The shuttle calls the vault over **plain `http://` on port `8080`**: `http://<VAULT_IP>:8080/`. The shuttle's sidecar proxy must originate TLS, that is, open the TLS connection itself, and deliver the request to port `8443`. Three Istio objects for this already exist in `starfleet`, all named `vault`, for the host `vault.outpost.example`:

* A `ServiceEntry` with the vault's address and two ports: `8080` (`HTTP`) and `8443` (`HTTPS`). **This `ServiceEntry` is correct.**
* A `VirtualService` that should route requests from port `8080` to port `8443`.
* A `DestinationRule` that should turn on TLS for requests to port `8443`.

Fix the problem so that:

1.  The `ServiceEntry` named `vault` is **left unchanged**.
2.  The `VirtualService` named `vault` matches requests on **port `8080`** and routes them to host `vault.outpost.example` on **port `8443`**.
3.  The `DestinationRule` named `vault` sets `tls` with `mode: SIMPLE` and `sni: vault.outpost.example` under `trafficPolicy.portLevelSettings` for **port `8443` only**. Port `8080` must not use TLS, and there must be no top-level `tls`. Keep `insecureSkipVerify: true`: the vault uses a self-signed certificate.
4.  In the `shuttle`'s proxy, the cluster for port `8443` of `vault.outpost.example` has a TLS transport socket, and the cluster for port `8080` has none.
5.  `GET http://<VAULT_IP>:8080/` from the `shuttle` returns **`200`**, and the response contains **`scheme=https`**.
6.  Do not change the `shuttle`, the `vault` pod, or the address the shuttle calls. Do not create a Service in `outpost`.

The grader sends real requests from the `shuttle` pod and reads the shuttle's proxy configuration, so the fix must work, not only exist.
