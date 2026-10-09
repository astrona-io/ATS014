# Question

Solve this question on: `terminal`

The `shuttle` in `starfleet` must reach the `relay` outside the mesh, and nothing else. The namespace `starfleet` refuses unknown hosts: its `Sidecar` resource named `default` sets `REGISTRY_ONLY`, so its sidecar proxies refuse every host that is not in the service registry. A `ServiceEntry` adds the relay to the registry, and a `VirtualService` gives every request to it a **2 second** timeout. Still, the `shuttle` pod's sidecar proxy refuses every request to the relay.

Your cluster has:

* `starfleet`: sidecar injection on. It holds the `shuttle` client, the `Sidecar` `default`, and the `VirtualService` `relay` for the host `relay.outpost.example`.
* `outpost`: sidecar injection **off**. It holds two bare pods with **no Service**, so neither is in the service registry. They stand in for external hosts, so this lab needs no internet access.
  * `relay`: the host the `shuttle` pod must reach.
  * `rogue`: a host that must stay blocked.
* `charts`: holds the `ServiceEntry` `relay` for `relay.outpost.example`.

Find the pod addresses with:

```bash
kubectl get pods -n outpost -o wide
```

There is more than one fault. Find each one with the `shuttle` pod's access log and `istioctl proxy-config`, then fix it.

**What the grader checks**

1. `GET http://<relay-ip>:8080/get` from `deploy/shuttle` in `starfleet` returns **200**.
2. `GET http://<relay-ip>:8080/delay/5` from the `shuttle` pod returns **504** after about **2 seconds**: the timeout in the `VirtualService` applies.
3. `GET http://<rogue-ip>:8080/get` from the `shuttle` pod does **not** return 200.
4. Exactly one `ServiceEntry` registers `relay.outpost.example`, with port `8080` declared as protocol **`HTTP`**. It must not list the rogue's address.
5. The `shuttle` pod's sidecar proxy has a listener on port `8080`.

**What must not change**

* The `Sidecar` `default` in `starfleet` stays, with `outboundTrafficPolicy.mode: REGISTRY_ONLY`, no `workloadSelector`, and no `*/*` in `egress.hosts`. Do not add a second `Sidecar`.
* The `VirtualService` `relay` keeps its host and its `2s` timeout.
* Leave the pods in `outpost` alone, and do not create a Service there.
