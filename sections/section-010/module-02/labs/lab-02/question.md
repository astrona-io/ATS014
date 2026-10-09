# Question

Solve this question on: `terminal`

The `shuttle` in `starfleet` can no longer reach the `probe` in `outpost`: `curl` gets no response at all. The `cargo` workload in the same namespace still reaches the `probe` without trouble.

Istio 1.30.5 is installed, and two namespaces have sidecar injection switched on:

* `starfleet`: `shuttle` (a client pod with `curl`) and `cargo` (a Service on port `9080`)
* `outpost`: `probe` v1 and v2 (a Service on port `8000`)

Two `Sidecar` objects exist in `starfleet`:

* `default`: the namespace-wide `Sidecar`. It lists `./*`, `istio-system/*` and `outpost/*`, and sets `outboundTrafficPolicy` to `REGISTRY_ONLY`. It is correct.
* `shuttle-only`: a `Sidecar` with a `workloadSelector` for `app: shuttle`. Something in it is wrong.

Repair the `shuttle` proxy's configuration, so that:

1.  The `Sidecar` **`shuttle-only`** still exists in `starfleet`, still selects only **`app: shuttle`**, and still sets `outboundTrafficPolicy` to **`REGISTRY_ONLY`**.
2.  `shuttle-only` lists the pod's **own namespace**, **`istio-system`** and the **`outpost`** namespace in its `egress` hosts.
3.  The `shuttle` proxy holds clusters for **`probe.outpost.svc.cluster.local`** and **`istiod.istio-system.svc.cluster.local`**.
4.  A request from `shuttle` to **`http://probe.outpost:8000/get`** gets **`200`**, and the `shuttle` proxy's access log shows it leaving through **`outbound|8000||probe.outpost.svc.cluster.local`**, not through a passthrough.
5.  `shuttle` still reaches `cargo` at **`http://cargo:9080/details/0`** with `200`.
6.  Leave the namespace-wide `Sidecar` `default` unchanged, and do not add another `Sidecar` to `starfleet`. Leave the Deployments, pod labels and Services unchanged.

The grader reads the `Sidecar` objects and the `shuttle` proxy's configuration, and sends live requests, so the configuration must really be repaired.
