# Question

Solve this question on: `terminal`

Every request from the `starfleet` namespace to the relay should leave the cluster through the egress gateway, so that the egress gateway's access log records it. All four objects for that route exist. Still, the `shuttle` pod's requests reach the relay without passing the egress gateway, and the egress gateway's access log stays empty.

An **egress gateway** is an Envoy proxy that outbound traffic to outside hosts can be sent through, so the traffic leaves the mesh at one point. It only carries the requests that a `VirtualService` sends to it.

Your cluster has:

* `istio-egress`: the egress gateway, Deployment and Service `istio-egress`, pods labelled `istio: egress`.
* `starfleet`: sidecar injection on. It holds the `shuttle` client pod and four objects for the host `relay.outpost.example`:
  * the `ServiceEntry` `relay` (port `8080`, protocol `HTTP`)
  * the `Gateway` `departure-gate`
  * the `DestinationRule` `departure-gate-for-relay`, with the subset `relay`
  * the `VirtualService` `relay-via-departure-gate`
* `outpost`: sidecar injection **off**. It holds `relay`, a bare pod with **no Service**, so it is not in the mesh's service registry. It stands in for a host outside the cluster, so this lab needs no internet access.

Send a test request with:

```bash
kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" http://relay.outpost.example:8080/get
```

There is more than one fault. Find each one with the access logs and the proxy configuration, then fix it.

**What the grader checks**

1. The `shuttle` sidecar's route for `relay.outpost.example` on port `8080` points at the egress gateway Service, subset `relay`.
2. `GET http://relay.outpost.example:8080/get` from `deploy/shuttle` in `starfleet` returns **200**.
3. The egress gateway's own access log gains a line for that request.
4. The `Gateway` `departure-gate` serves the host `relay.outpost.example`.

**What must not change**

* Keep the object names. Fix the existing `Gateway` and `VirtualService`; do not add a second one of either kind in `starfleet`.
* The `ServiceEntry` `relay` and the `DestinationRule` `departure-gate-for-relay` are correct. Leave them in place.
* Leave the `relay` pod in `outpost` alone, and do not create a Service there.
