# Question

Solve this question on: `terminal`

The fleet's integration layer must reach a partner's API and one of your own old machines, while every other outside host stays blocked.

Istio 1.30.5 is installed, and the mesh blocks every outbound destination that is not in the service registry (`outboundTrafficPolicy.mode: REGISTRY_ONLY`). The service registry is the list of hosts and endpoints that `istiod` sends to every sidecar proxy. Three endpoints exist, none of them is in the registry, and so all three are blocked.

The namespace **`integrations`** has sidecar injection switched on and holds:

* `tester`: a client pod with `curl` and a sidecar proxy. Send your test requests from here.
* `legacy-vm`: a pod **without a sidecar proxy**, running as the ServiceAccount **`legacy-sa`** and answering HTTP on port **8080**. It is **your** machine and stands in for a virtual machine. Its IP address is in `/tmp/vm-ip`.
* A `DestinationRule` named `legacy-plaintext` that sets `tls` mode `DISABLE` for the host `legacy.integrations.svc`. The stand-in pod cannot accept mTLS (mutual TLS), so this object is part of the environment, not of the task. Leave it in place.

The namespace **`outside-mesh`** has no sidecar injection and no Services. It holds:

* `partner-api`: an endpoint that accepts **only TLS** on port **8443**. A plain HTTP request to it fails. It answers with the scheme it was reached over. Its IP address is in `/tmp/partner-ip`.
* `blocked-api`: HTTP on port 8080. It must **stay** blocked. Its IP address is in `/tmp/blocked-ip`.

Deliver all three results.

**A: The partner API, reached over plain HTTP**

1.  A `ServiceEntry` named **`partner`** in `integrations` for the host **`partner.example.com`**, with the partner address in `spec.addresses`, `location` **`MESH_EXTERNAL`**, `resolution` **`STATIC`**, an `endpoints` entry for that address, and **`exportTo: ["."]`**.
2.  Two ports on it: **8080** with name `http` and protocol **`HTTP`**, and **8443** with name `https` and protocol **`HTTPS`**.
3.  A `VirtualService` named **`partner`** that matches **port 8080** and routes to **port 8443** on the same host.
4.  A `DestinationRule` named **`partner`** with `trafficPolicy.portLevelSettings` for **port 8443** only: `tls.mode` **`SIMPLE`**, `tls.sni` **`partner.example.com`**, and `insecureSkipVerify: true` (the certificate is self-signed).

**B: Your machine, as a member of the mesh**

5.  A `WorkloadEntry` named **`legacy-vm`** in `integrations` with the address of the machine, the label **`app: legacy`**, and `serviceAccount` **`legacy-sa`**.
6.  A `ServiceEntry` named **`legacy`** in `integrations` for the host **`legacy.integrations.svc`**, with `location` **`MESH_INTERNAL`**, `resolution` **`STATIC`**, port **8080** with name `http` and protocol `HTTP`, and a `workloadSelector` that matches `app: legacy`.

**C: Keep the third endpoint blocked**

7.  Do not add `blocked-api` to the service registry, and do not change the mesh to `ALLOW_ANY`.

**What the grader checks**

8.  The mesh is still `REGISTRY_ONLY`.
9.  `GET http://<partner-ip>:8080/` from `tester` returns **200**, and the body contains **`scheme=https`**. A plain HTTP request reached an endpoint that only accepts TLS, so the sidecar proxy originated the TLS connection.
10. The `tls` block of the partner `DestinationRule` is under `portLevelSettings` for port 8443, not at the top level of `trafficPolicy`.
11. `GET http://legacy.integrations.svc:8080/get` returns **200**: the machine is reachable by host name.
12. The legacy `ServiceEntry` is `MESH_INTERNAL`, and the `WorkloadEntry` carries `serviceAccount: legacy-sa`.
13. `GET http://<blocked-ip>:8080/get` does **not** return 200.
14. No Service exists in `outside-mesh`, and `legacy-vm` still has no sidecar proxy.
