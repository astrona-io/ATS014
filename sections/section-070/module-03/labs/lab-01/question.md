# Question

Solve this question on: `terminal`

Two old machines run outside the fleet's Kubernetes cluster. Add them to the mesh as one service, with an identity that Istio policies can name.

Istio 1.30.5 is installed. The namespace `vm-demo` has sidecar injection switched on and holds:

* `tester`: a client pod with `curl` and a sidecar proxy. Send your test requests from here.
* `legacy-sa`: a ServiceAccount.
* `legacy-vm-1` and `legacy-vm-2`: two pods **excluded from sidecar injection**, running as `legacy-sa` and answering HTTP on port **8080**. They have **no Service** and no sidecar proxy, and they stand in for two virtual machines. Their IP addresses are in the files **`/tmp/vm1-ip`** and **`/tmp/vm2-ip`**.
* A `DestinationRule` named `legacy-plaintext` that sets `tls` mode `DISABLE` for the host `legacy.vm-demo.svc`. The stand-in pods cannot accept mTLS (mutual TLS), so this object is part of the environment, not of the task. Leave it in place.

Pods can reach the two machines by IP address, but the mesh knows nothing about them. No `WorkloadEntry`, `ServiceEntry` or `WorkloadGroup` exists.

Add both machines to the mesh as one service:

1.  Create **two** `WorkloadEntry` objects in `vm-demo`, named **`legacy-vm-1`** and **`legacy-vm-2`**, each with:
    *   `address` set to the IP address of the matching machine
    *   the label **`app: legacy-backend`**
    *   `serviceAccount` **`legacy-sa`**. This field gives the workload its identity in the mesh.
2.  Create a `ServiceEntry` named **`legacy`** in `vm-demo` for the host **`legacy.vm-demo.svc`**, with:
    *   `location` **`MESH_INTERNAL`**, because these are your own workloads, not somebody else's service
    *   `resolution` **`STATIC`**
    *   one port: number **8080**, name `http`, protocol **`HTTP`**
    *   a `workloadSelector` that matches the label **`app: legacy-backend`**
3.  Create a `WorkloadGroup` named **`legacy`** in `vm-demo` whose template matches those entries: labels `app: legacy-backend`, `serviceAccount` `legacy-sa`, port `http: 8080`. No machine registers against it here, because the stand-in pods do not run `istio-agent`, but a real group of virtual machines needs it.

**What the grader checks**

4.  Both `WorkloadEntry` objects exist with the correct address, label and ServiceAccount.
5.  The `ServiceEntry` has `location: MESH_INTERNAL`. `MESH_EXTERNAL` routes requests too, but gives the workloads no identity, so the grader does not accept it.
6.  `resolution` is `STATIC`, the port is `8080` with protocol `HTTP`, and the `workloadSelector` matches the label of the entries.
7.  `GET http://legacy.vm-demo.svc:8080/get` from `tester` returns **200**. The host name resolves, which it did not before.
8.  The cluster for `legacy.vm-demo.svc` in the `tester` sidecar proxy has **two** endpoints, one per machine.
9.  The `WorkloadGroup` exists, and the labels, ServiceAccount and port of its template match the entries.
10. Both stand-in pods still run without a sidecar proxy, and no Service was created for them.
