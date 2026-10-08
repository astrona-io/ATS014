# Question

Solve this question on: `terminal`

Astronaut, your mission: bring two old ships that fly outside the fleet network onto the star chart, with crew papers mission control recognises.

Namespace `vm-demo` holds:

* `tester` — an injected client pod with `curl`
* `legacy-sa` — a ServiceAccount
* `legacy-vm-1` and `legacy-vm-2` — two pods **excluded from injection**, running as `legacy-sa`, answering HTTP on **8080**. They have **no Service** and no sidecar, and stand in for two virtual machines. Their addresses are in **`/tmp/vm1-ip`** and **`/tmp/vm2-ip`**.

They are reachable by address and completely unknown to the mesh. No `WorkloadEntry`, `ServiceEntry` or `WorkloadGroup` exists.

Bring both machines into the mesh as one service: one beacon both ships answer to.

1.  Create **two** `WorkloadEntry` objects in `vm-demo`, named **`legacy-vm-1`** and **`legacy-vm-2`**, each with:
    *   `address` set to the matching machine's IP
    *   the label **`app: legacy-backend`**
    *   `serviceAccount` **`legacy-sa`** — this is what gives the workload a mesh identity
2.  Create a `ServiceEntry` named **`legacy`** in `vm-demo` for host **`legacy.vm-demo.svc`**, with:
    *   `location` **`MESH_INTERNAL`** — these are your workloads, not somebody else's service
    *   `resolution` **`STATIC`**
    *   one port: number **8080**, name `http`, protocol **`HTTP`**
    *   a `workloadSelector` matching the label **`app: legacy-backend`**
3.  Create a `WorkloadGroup` named **`legacy`** in `vm-demo` whose template would produce those same entries: labels `app: legacy-backend`, `serviceAccount` `legacy-sa`, port `http: 8080`. Nothing will auto-register against it here — the stand-ins do not run `istio-agent` — but it is the object a real fleet needs.

**What the grader checks**

4.  Both `WorkloadEntry` objects exist with the right address, label and service account.
5.  The `ServiceEntry` has `location: MESH_INTERNAL`. `MESH_EXTERNAL` would route correctly and give the workloads no identity — it is not acceptable.
6.  `resolution` is `STATIC` and the `workloadSelector` matches the entries' label.
7.  `GET http://legacy.vm-demo.svc:8080/get` from `tester` returns **200** — the host resolves by name, which it could not before.
8.  The `tester` proxy's cluster for `legacy.vm-demo.svc` has **two** endpoints, one per machine.
9.  The `WorkloadGroup` exists with a template whose labels, service account and port match the entries.
10. Both stand-in pods are still running and no Service was created for them.
