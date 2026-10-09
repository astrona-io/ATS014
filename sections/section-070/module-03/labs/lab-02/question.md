---
estimated_duration: 20m
---

# Question

Solve this question on: `terminal`

Astronaut, the fleet has two old freighters that fly outside the fleet network. A crew mate put them on the star chart under the name `freighter.starfleet.mesh`, and went off shift. Now every signal to that name fails with `503`.

The planet `starfleet` holds:

* `shuttle`: a client pod with `curl` and a sidecar. Send your test signals from here.
* `freighter-vm-1` and `freighter-vm-2`: two Deployments whose pods have **no sidecar** and **no Service**. They stand in for two virtual machines, answer HTTP on port **8080**, and run as the ServiceAccount `freighter`. Their `/hostname` path answers with the pod's name.

Istio 1.30.5 is installed, and the shuttle's sidecar answers name lookups from the mesh registry. These Istio objects already exist in `starfleet`:

* Two `WorkloadEntry` objects, `freighter-vm-1` and `freighter-vm-2`, one per freighter. Their addresses and ServiceAccount are correct.
* A `ServiceEntry` named `freighter` for the host `freighter.starfleet.mesh`, port `8080`, protocol `HTTP`.
* A `DestinationRule` named `freighter` that sets `tls` mode `DISABLE` for `freighter.starfleet.mesh`. The stand-ins cannot answer mutual TLS, so **this object is correct and must stay**.

More than one thing is wrong. Fix the setup so that:

1.  The `shuttle`'s proxy holds **exactly two** endpoints in the cluster `outbound|8080||freighter.starfleet.mesh`: the addresses of the `freighter-vm-1` and `freighter-vm-2` pods.
2.  20 out of 20 signals from `shuttle` to `http://freighter.starfleet.mesh:8080/hostname` are answered, and **both** freighters answer at least once.
3.  The `ServiceEntry` named `freighter` has `location: MESH_INTERNAL`. The freighters are the fleet's own machines, not strangers.
4.  The `ServiceEntry` keeps `resolution: STATIC`, and its `workloadSelector` is exactly `app: freighter`.
5.  Both `WorkloadEntry` objects carry the label `app: freighter`, and keep their addresses and the ServiceAccount `freighter`.

Do not change:

* The Deployments and their pods. Do not inject a sidecar into the freighters.
* The `DestinationRule` named `freighter`.

Do not create a Kubernetes Service for the freighters.
