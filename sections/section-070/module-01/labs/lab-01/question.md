# Question

Solve this question on: `terminal`

Your application must call one partner API outside the mesh, and nothing else. The mesh is already set to refuse unknown hosts: `meshConfig.outboundTrafficPolicy.mode` is `REGISTRY_ONLY`, so the sidecar proxy refuses every destination that is not in the service registry. The service registry is the list of hosts that `istiod`, Istio's control plane, knows about.

Your cluster has two namespaces:

* `egress-demo`: sidecar injection on. It holds a `tester` client pod with `curl`.
* `outside-mesh`: sidecar injection **off**. It holds two bare pods with **no Service**, so neither is in the service registry. They stand in for external endpoints, so this lab needs no internet access.
  * `partner-api`: the endpoint you must allow.
  * `forbidden-api`: the endpoint that must stay blocked.

Their addresses are in **`/tmp/partner-ip`** and **`/tmp/forbidden-ip`**, and the bootstrap output prints them too. Both now return **502** from `tester`, because the mesh refuses them.

Add the partner endpoint to the registry, and only that one:

1.  Create a `ServiceEntry` named **`partner-api`** in the namespace **`egress-demo`**.
2.  Give it the host **`partner.example.com`**.
3.  Add the partner pod's address to **`spec.addresses`** as a plain IP address (for example `10.244.0.12`), so the sidecar proxy can match traffic sent to that address.
4.  Declare **one port**: number **8080**, name **`http`**, protocol **`HTTP`**. The protocol matters, because step 7 depends on it.
5.  Set `location` to **`MESH_EXTERNAL`** and `resolution` to **`STATIC`**, with one `endpoints` entry whose `address` is the partner pod's address.
6.  Limit the entry to its own namespace with **`exportTo: ["."]`**. A `ServiceEntry` is exported to every namespace by default, and this one must not be.
7.  Create a `VirtualService` named **`partner-api`** in `egress-demo` for the host **`partner.example.com`**, with a **`timeout` of `2s`** and a route to that host.

**What the grader checks**

8.  The mesh is still `REGISTRY_ONLY`. Do not change it to make the task pass.
9.  `GET http://<partner-ip>:8080/get` from `tester` returns **200**.
10. `GET http://<forbidden-ip>:8080/get` from `tester` does **not** return 200: allowing one endpoint must not open the other.
11. `GET http://<partner-ip>:8080/delay/5` returns **504** after about **2 seconds**. This proves the `VirtualService` timeout applies to the host, and it only works because the port is declared `HTTP`.
12. The `ServiceEntry` has `location: MESH_EXTERNAL`, `resolution: STATIC` and `exportTo: ["."]`.
13. `partner.example.com` appears in the cluster list of the `tester` pod's sidecar proxy.

**What must not change**

* Do not create a Service in `outside-mesh`.
