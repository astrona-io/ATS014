# Question

Solve this question on: `terminal`

The mesh is already configured **deny-by-default**: `meshConfig.outboundTrafficPolicy.mode` is `REGISTRY_ONLY`, so any destination not in the mesh registry is refused.

* `egress-demo` — injected, holds a `tester` client pod with `curl`
* `outside-mesh` — **not** injected, holds two bare pods with **no Service**, so neither is in the mesh registry. They stand in for external endpoints, and this lab needs no internet access.
  * `partner-api` — the one you must allow
  * `forbidden-api` — must stay blocked

Their addresses are in **`/tmp/partner-ip`** and **`/tmp/forbidden-ip`**, and are printed in the bootstrap output. Both currently return **502** from `tester`, because the mesh refuses them.

Register the partner endpoint, and only that one.

1.  Create a `ServiceEntry` named **`partner-api`** in namespace **`egress-demo`**.
2.  Give it the host **`partner.example.com`**.
3.  Add the partner pod's address to **`spec.addresses`** (as a plain IP, e.g. `10.244.0.12`) so the sidecar recognises traffic aimed at it.
4.  Declare **one port**: number **8080**, name **`http`**, protocol **`HTTP`**. The protocol matters — step 7 depends on it.
5.  Set `location` to **`MESH_EXTERNAL`** and `resolution` to **`STATIC`**, with a single `endpoints` entry whose `address` is the partner pod's address.
6.  Restrict the entry to its own namespace with **`exportTo: ["."]`**. A `ServiceEntry` is exported mesh-wide by default, and this one should not be.
7.  Create a `VirtualService` named **`partner-api`** in `egress-demo` for host **`partner.example.com`**, applying a **`timeout` of `2s`** and routing to that host.

**What the grader checks**

8.  The mesh is still `REGISTRY_ONLY`. Do not relax it to make the task pass.
9.  `GET http://<partner-ip>:8080/get` from `tester` returns **200**.
10. `GET http://<forbidden-ip>:8080/get` from `tester` does **not** return 200 — registering one endpoint must not open the other.
11. `GET http://<partner-ip>:8080/delay/5` returns **504** in roughly **2 seconds**, proving the `VirtualService` timeout applies to the registered host. This only works because the port was declared `HTTP`.
12. The `ServiceEntry` has `location: MESH_EXTERNAL`, `resolution: STATIC` and `exportTo: ["."]`.
13. `partner.example.com` appears in the `tester` proxy's cluster list.
