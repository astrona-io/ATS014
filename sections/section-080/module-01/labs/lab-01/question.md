# Question

Solve this question on: `terminal`

* `egwgw-demo` (injected) — two clients:
  * `tester`, whose pods carry the labels `app: tester` **and `egress-allowed: "true"`**
  * `other-client`, whose pods carry only `app: other-client`
* `outside-mesh` (not injected) — `partner-api`, a bare pod with **no Service** on port **8080**, standing in for an external endpoint. Address in **`/tmp/partner-ip`**.
* `istio-egressgateway` is running in `istio-system` and currently carries **no traffic**.

There is no `ServiceEntry`, `Gateway`, `DestinationRule` or `VirtualService`. This lab needs no internet access.

Your mission, astronaut: send signals to the partner endpoint through the solar system's departure gate (the egress gateway) — and only from the spaceship that is allowed to.

1.  A `ServiceEntry` named **`partner`** in `egwgw-demo` for host **`partner.example.com`**, with the partner address in `spec.addresses`, port **8080** name `http` protocol **`HTTP`**, `location` **`MESH_EXTERNAL`**, `resolution` **`STATIC`**, and an `endpoints` entry for that address.
2.  A `Gateway` named **`egress-gateway`** in `egwgw-demo`, selecting **`istio: egressgateway`**, opening port **8080**, protocol **`HTTP`**, for host **`partner.example.com`** — the **external** hostname, not an internal one.
3.  A `DestinationRule` named **`egressgateway-for-partner`** in `egwgw-demo` for host `istio-egressgateway.istio-system.svc.cluster.local`, with a single subset named **`partner`** and no labels.
4.  A `VirtualService` named **`partner-through-egress`** in `egwgw-demo` for host `partner.example.com`, listing **both** `mesh` and `egress-gateway` in its top-level `gateways`, with exactly **two** `http` rules:
    *   **Stage 1** — `match` on port **8080** **and `sourceLabels: {egress-allowed: "true"}`** — routes to `istio-egressgateway.istio-system.svc.cluster.local`, subset **`partner`**, port **8080**. Match on the **port and `sourceLabels` only** — do **not** add `gateways: [mesh]` here. On Istio 1.30.5 combining it with `sourceLabels` makes the label predicate be ignored and every sidecar gets the diverting route. The rule still cannot fire on the gateway itself, because the gateway pod does not carry that label.
    *   **Stage 2** — `match` on `gateways: [egress-gateway]`, port **8080** — routes to `partner.example.com` port **8080**.

**What the grader checks**

5.  `GET http://partner.example.com:8080/get` from **`tester`** returns **200**. The mesh resolves that name from the `ServiceEntry`, and the hostname is what the gateway's route matches on — an IP authority matches nothing.
6.  The **gateway's own access log** gains a line for that request — the hop really happened.
7.  The `tester` sidecar's route for the external host points at the **egress gateway Service**, not at the partner address.
8.  `GET http://partner.example.com:8080/get` from **`other-client`** also returns **200**, and produces **no** new gateway log line. It does not match `sourceLabels`, so it takes the direct path — `sourceLabels` narrows the route, not the permission.
9.  The `Gateway` object's `servers[].hosts` names `partner.example.com`.
10. The `VirtualService` lists both `mesh` and the gateway in its top-level `gateways`.
