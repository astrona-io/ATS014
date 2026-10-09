---
estimated_duration: 20m
---

# Question

Solve this question on: `terminal`

Astronaut, the crew on the planet `starfleet` reports trouble. The shuttle must reach a vault on the planet `outpost`, and every signal it sends fails.

The cluster holds two planets:

* `starfleet`: sidecar injection on. It holds `shuttle`, a client pod with `curl`. Send your test signals from here.
* `outpost`: **no** sidecar injection. It holds a bare pod `vault` with **no Service**, so the vault is not on the star chart by itself.

The `vault` listens **only on port `8443`, with TLS**. A plain HTTP signal to that port gets `400`. It answers every signal with the scheme it was reached over, for example `vault: scheme=https`, so you can see whether the seal was added. Get its address with:

```sh
kubectl get pod vault -n outpost -o jsonpath='{.status.podIP}'
```

The shuttle calls the vault over **plain `http://` on port `8080`**: `http://<VAULT_IP>:8080/`. Its communications officer must seal the signal with TLS and deliver it to port `8443`. Three Istio objects for this already exist in `starfleet`, all named `vault`, for the host `vault.outpost.example`:

* A `ServiceEntry` with the vault's address and two ports: `8080` (`HTTP`) and `8443` (`HTTPS`). **This `ServiceEntry` is correct.**
* A `VirtualService` that should move signals from port `8080` to port `8443`.
* A `DestinationRule` that should seal signals to port `8443` with TLS.

Fix the problem so that:

1.  The `ServiceEntry` named `vault` is **left unchanged**.
2.  The `VirtualService` named `vault` matches signals on **port `8080`** and routes them to host `vault.outpost.example` on **port `8443`**.
3.  The `DestinationRule` named `vault` sets `tls` with `mode: SIMPLE` and `sni: vault.outpost.example` under `trafficPolicy.portLevelSettings` for **port `8443` only**. Port `8080` must not be sealed, and there must be no top-level `tls`. Keep `insecureSkipVerify: true`: the vault uses a self-signed certificate.
4.  In the `shuttle`'s proxy, the cluster for port `8443` of `vault.outpost.example` has a TLS transport socket, and the cluster for port `8080` has none.
5.  `GET http://<VAULT_IP>:8080/` from the `shuttle` returns **`200`**, and the answer contains **`scheme=https`**.
6.  Do not change the `shuttle`, the `vault` pod, or the address the shuttle calls. Do not create a Service in `outpost`.

The grader sends live signals from the `shuttle` pod and reads the shuttle's proxy, so the fix has to work, not merely exist.
