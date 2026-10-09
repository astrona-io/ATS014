# Question

Solve this question on: `terminal`

Astronaut, the planet `starfleet` is closed: its `Sidecar` named `default` sets `REGISTRY_ONLY`, so its ships may signal only charted planets. One planet in another solar system should be on that chart: the **relay**. A `ServiceEntry` for it exists, and a flight plan (`VirtualService`) gives every signal to it a **2 second** timeout. Still, every signal from the shuttle to the relay falls into the black hole.

Your cluster has:

* `starfleet`: injected. It holds the `shuttle` client, the `Sidecar` `default`, and the `VirtualService` `relay` for the host `relay.outpost.example`.
* `outpost`: **not** injected. It holds two bare pods with **no Service**, so neither is in the mesh registry. They stand in for hosts in another solar system, and this lab needs no internet access.
  * `relay`: the host the shuttle must reach.
  * `rogue`: a host that must stay blocked.
* `charts`: holds the `ServiceEntry` `relay` for `relay.outpost.example`.

Find the pod addresses with:

```bash
kubectl get pods -n outpost -o wide
```

There is more than one fault. Find each one with the flight log and the shuttle's proxy, then fix it.

**What the grader checks**

1. `GET http://<relay-ip>:8080/get` from `deploy/shuttle` in `starfleet` returns **200**.
2. `GET http://<relay-ip>:8080/delay/5` from the shuttle returns **504** after about **2 seconds**: the timeout in the `VirtualService` applies.
3. `GET http://<rogue-ip>:8080/get` from the shuttle does **not** return 200.
4. Exactly one `ServiceEntry` registers `relay.outpost.example`, with port `8080` declared as protocol **`HTTP`**. It must not list the rogue's address.
5. The shuttle's proxy has a listener on port `8080`.

**What must not change**

* The `Sidecar` `default` in `starfleet` stays, with `outboundTrafficPolicy.mode: REGISTRY_ONLY`, no `workloadSelector`, and no `*/*` in `egress.hosts`. Do not add a second `Sidecar`.
* The `VirtualService` `relay` keeps its host and its `2s` timeout.
* Leave the pods in `outpost` alone, and do not create a Service there.
