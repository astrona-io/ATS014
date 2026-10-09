# Question

Solve this question on: `terminal`

The fleet has two old freighters that run outside Kubernetes. A colleague added them to the mesh under the host name `freighter.starfleet.mesh` and went home. Now every request to that name fails with `503`.

The `starfleet` namespace holds:

* `shuttle`: a client pod with `curl` and a sidecar proxy. Send your test requests from here.
* `freighter-vm-1` and `freighter-vm-2`: two Deployments whose pods have **no sidecar proxy** and **no Service**. They stand in for two virtual machines, answer HTTP on port **8080**, and run as the ServiceAccount `freighter`. Their `/hostname` path returns the pod name.

Istio 1.30.5 is installed, and the `shuttle` sidecar proxy answers DNS lookups for hosts in the service registry. These Istio objects already exist in `starfleet`:

* Two `WorkloadEntry` objects, `freighter-vm-1` and `freighter-vm-2`, one per freighter pod. Their addresses and ServiceAccount are correct.
* A `ServiceEntry` named `freighter` for the host `freighter.starfleet.mesh`, port `8080`, protocol `HTTP`.
* A `DestinationRule` named `freighter` that sets `tls` mode `DISABLE` for `freighter.starfleet.mesh`. The stand-in pods cannot accept mTLS (mutual TLS), so **this object is correct and must stay**.

More than one setting is wrong. Fix the setup so that:

1.  The `shuttle` sidecar proxy holds **exactly two** endpoints in the cluster `outbound|8080||freighter.starfleet.mesh`: the addresses of the `freighter-vm-1` and `freighter-vm-2` pods.
2.  20 out of 20 requests from `shuttle` to `http://freighter.starfleet.mesh:8080/hostname` get an answer, and **both** freighter pods answer at least once.
3.  The `ServiceEntry` named `freighter` has `location: MESH_INTERNAL`. The freighters are your own machines, not somebody else's service.
4.  The `ServiceEntry` keeps `resolution: STATIC`, and its `workloadSelector` is exactly `app: freighter`.
5.  Both `WorkloadEntry` objects carry the label `app: freighter`, and keep their addresses and the ServiceAccount `freighter`.

Do not change:

* The Deployments and their pods. Do not inject a sidecar proxy into the freighter pods.
* The `DestinationRule` named `freighter`.

Do not create a Kubernetes Service for the freighter pods.
