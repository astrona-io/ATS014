# Question

Solve this question on: `terminal`

Astronaut, every signal from the planet `starfleet` to the relay should leave the solar system through the departure gate (the egress gateway), so that the gate's flight log records it. All four objects for that route exist. Still, the shuttle's signals reach the relay without ever passing the gate, and the gate's flight log stays empty.

Your cluster has:

* `istio-egress`: the egress gateway, Deployment and Service `istio-egress`, pods labelled `istio: egress`.
* `starfleet`: injected. It holds the `shuttle` client and four objects for the host `relay.outpost.example`:
  * the `ServiceEntry` `relay` (port `8080`, protocol `HTTP`)
  * the `Gateway` `departure-gate`
  * the `DestinationRule` `departure-gate-for-relay`, with the subset `relay`
  * the `VirtualService` `relay-via-departure-gate`
* `outpost`: **not** injected. It holds the `relay`, a bare pod with **no Service**, so it is not in the mesh registry. It stands in for a host in another solar system, and this lab needs no internet access.

Send a test signal with:

```bash
kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" http://relay.outpost.example:8080/get
```

There is more than one fault. Find each one with the flight logs and the proxies' configuration, then fix it.

**What the grader checks**

1. The shuttle's route for `relay.outpost.example` on port `8080` points at the egress gateway Service, subset `relay`.
2. `GET http://relay.outpost.example:8080/get` from `deploy/shuttle` in `starfleet` returns **200**.
3. The egress gateway's own access log gains a line for that signal.
4. The `Gateway` `departure-gate` serves the host `relay.outpost.example`.

**What must not change**

* Keep the object names. Fix the existing `Gateway` and `VirtualService`; do not add a second one of either kind in `starfleet`.
* The `ServiceEntry` `relay` and the `DestinationRule` `departure-gate-for-relay` are correct. Leave them in place.
* Leave the relay pod in `outpost` alone, and do not create a Service there.
