# Question

Solve this question on: `terminal`

Requests to a partner endpoint outside the mesh must leave the cluster through the egress gateway, but only from the one client that is allowed to use it. Istio 1.30.5 is installed with the `demo` profile. The cluster has:

* `egwgw-demo` (sidecar injection on), with two clients:
  * `tester`, whose pods carry the labels `app: tester` **and `egress-allowed: "true"`**
  * `other-client`, whose pods carry only `app: other-client`
* `outside-mesh` (sidecar injection off), with `partner-api`: a bare pod with **no Service**, listening on port **8080**. It stands in for an external endpoint. Its address is in **`/tmp/partner-ip`**.
* `istio-egressgateway` in `istio-system`: the egress gateway. It is running and carries **no traffic** yet.

An **egress gateway** is an Envoy proxy that outbound traffic to outside hosts can be sent through, so the traffic leaves the mesh at one point. There is no `ServiceEntry`, `Gateway`, `DestinationRule` or `VirtualService`. This lab needs no internet access.

Create these four objects:

1.  A `ServiceEntry` named **`partner`** in `egwgw-demo` for host **`partner.example.com`**, with the partner address in `spec.addresses`, port **8080** name `http` protocol **`HTTP`**, `location` **`MESH_EXTERNAL`**, `resolution` **`STATIC`**, and an `endpoints` entry for that address.
2.  A `Gateway` named **`egress-gateway`** in `egwgw-demo`, selecting **`istio: egressgateway`**, opening port **8080**, protocol **`HTTP`**, for host **`partner.example.com`**. This is the **outside** host name, not an internal one.
3.  A `DestinationRule` named **`egressgateway-for-partner`** in `egwgw-demo` for host `istio-egressgateway.istio-system.svc.cluster.local`, with a single subset named **`partner`** and no labels.
4.  A `VirtualService` named **`partner-through-egress`** in `egwgw-demo` for host `partner.example.com`. Its top-level `gateways` lists **both** `mesh` and `egress-gateway`, and it has exactly **two** `http` rules:
    *   **Stage 1**: `match` on port **8080** **and `sourceLabels: {egress-allowed: "true"}`**. It routes to `istio-egressgateway.istio-system.svc.cluster.local`, subset **`partner`**, port **8080**. Match on the **port and `sourceLabels` only**, and do **not** add `gateways: [mesh]` here. On Istio 1.30.5, combining `gateways: [mesh]` with `sourceLabels` in an `http` rule makes Istio ignore the label, so every sidecar gets the route to the egress gateway. The rule still does not run on the egress gateway, because the egress gateway pod does not carry that label.
    *   **Stage 2**: `match` on `gateways: [egress-gateway]` and port **8080**. It routes to `partner.example.com` port **8080**.

**What the grader checks**

5.  `GET http://partner.example.com:8080/get` from **`tester`** returns **200**. The mesh resolves that name from the `ServiceEntry`, and the egress gateway's route matches on the host name, so a request to the IP address matches nothing.
6.  The **egress gateway's own access log** gains a line for that request, which proves the extra hop happened.
7.  The `tester` sidecar's route for the outside host points at the **egress gateway Service**, not at the partner address.
8.  `GET http://partner.example.com:8080/get` from **`other-client`** also returns **200**, and adds **no** new line to the egress gateway's access log. Its pods do not match `sourceLabels`, so its requests go direct. `sourceLabels` limits the route, not the permission.
9.  The `Gateway` object's `servers[].hosts` names `partner.example.com`.
10. The `VirtualService` lists both `mesh` and the egress gateway in its top-level `gateways`.
