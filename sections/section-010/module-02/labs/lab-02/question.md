---
estimated_duration: 15m
---

# Question

Solve this question on: `terminal`

Astronaut, a shuttle has lost its way. On the planet `starfleet`, the shuttle's signals to the probe on the planet `outpost` fall into a black hole: `curl` gets no answer at all. The cargo ship on the same planet can still reach the probe.

The solar system holds two planets, both with sidecar injection:

* `starfleet` — `shuttle` (a client with `curl`) and `cargo` (a Service on port `9080`)
* `outpost` — `probe` v1 and v2 (a Service on port `8000`)

Two `Sidecar` objects exist on `starfleet`:

* `default` — the planet default. It lists `./*`, `istio-system/*` and `outpost/*`, and sets `outboundTrafficPolicy` to `REGISTRY_ONLY`. It is correct.
* `shuttle-only` — a `Sidecar` with a `workloadSelector` for `app: shuttle`. Something in it is wrong.

Repair the shuttle's star chart, so that:

1.  The `Sidecar` **`shuttle-only`** still exists in `starfleet`, still selects only **`app: shuttle`**, and still sets `outboundTrafficPolicy` to **`REGISTRY_ONLY`**.
2.  `shuttle-only` lists the shuttle's **own planet**, **`istio-system`** and the **`outpost`** planet in its `egress` hosts.
3.  The shuttle's proxy holds destinations for **`probe.outpost.svc.cluster.local`** and **`istiod.istio-system.svc.cluster.local`**.
4.  A signal from the shuttle to **`http://probe.outpost:8000/get`** gets **`200`**, and the shuttle's flight log shows it leaving through **`outbound|8000||probe.outpost.svc.cluster.local`**, not through a passthrough.
5.  The shuttle still reaches the cargo ship at **`http://cargo:9080/details/0`** with `200`.
6.  Leave the planet default `Sidecar` `default` unchanged, and do not add another `Sidecar` to `starfleet`. Leave the Deployments, pod labels and Services unchanged.

The grader reads the `Sidecar` objects and the shuttle's proxy, and sends live signals, so the star chart has to really be repaired.
