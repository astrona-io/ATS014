# Restricting, Proving And The Trade-Off

The configuration works, and from outside it looks exactly like not having it. This part gives you the evidence, the mistakes that hide behind a `200`, the way to narrow which spaceships use the path, and an honest account of what the arrangement costs.

## Proving the hop happened

The gateway's own access log, its black box flight log, is the direct evidence. It is also the reason the whole arrangement exists. Part 2's checkpoint already showed it: `log_hop2_egress` printed a line ending in `outbound|443||httpbin.org`. **That log — one place, not every sidecar — is the audit trail.** It also names the calling pod's address, so you know which spaceship sent each signal.

But a `200` proves nothing on its own. The next mistake returns `200` too.

> [!TIP]
> **Try it — `mesh` missing: it works, and skips the gateway**
>
> Save this as `virtualservice-without-mesh.yaml`:
>
> ```yaml
> apiVersion: networking.istio.io/v1
> kind: VirtualService
> metadata:
>   name: httpbin-org-via-egress
>   namespace: bookinfo
> spec:
>   hosts:
>     - httpbin.org
>   gateways:
>     - egress-gateway
>   tls:
>     - match:
>         - gateways: [mesh]
>           port: 443
>           sniHosts: [httpbin.org]
>       route:
>         - destination:
>             host: istio-egress.istio-egress.svc.cluster.local
>             subset: httpbin-org
>             port:
>               number: 443
>     - match:
>         - gateways: [egress-gateway]
>           port: 443
>           sniHosts: [httpbin.org]
>       route:
>         - destination:
>             host: httpbin.org
>             port:
>               number: 443
> ```
>
> Apply it:
>
> ```sh
> kubectl apply -f virtualservice-without-mesh.yaml
> ```
>
> Then check the result:
>
> ```sh
> call_external
> log_hop1_sidecar
> ```
>
> Expect `200` — looks fine — and then a hop-1 line that goes **straight out**:
>
> ```text
> ... "54.175.207.120:443" outbound|443||httpbin.org ...
> ```
>
> The top-level `gateways` list is where the `VirtualService` applies. Without `mesh`, the sidecars ignore the whole object, so the hop-1 rule inside it never runs. curl goes direct, which the `ServiceEntry` still allows. **Always check hop 1 in the log.**

The applied object has the same name as Part 2's, so it replaced it. Put the working version back before the next experiment: `kubectl apply -f virtualservice-httpbin-org-via-egress.yaml`.

## When "via egress" breaks

The opposite mistakes do fail. But the failure shows up at the client as a bare TLS error, so you need the flight logs to know which leg is missing.

**Hop 2 missing.** Keep only the `mesh` rule, and the sidecar still sends the signal to the gate. But the gate has no flight plan onward for `httpbin.org`. With nowhere to send it, the gate closes the connection during the TLS handshake.

> [!TIP]
> **Try it — hop 2 missing**
>
> Save this as `virtualservice-missing-hop-2.yaml`:
>
> ```yaml
> apiVersion: networking.istio.io/v1
> kind: VirtualService
> metadata:
>   name: httpbin-org-via-egress
>   namespace: bookinfo
> spec:
>   hosts:
>     - httpbin.org
>   gateways:
>     - mesh
>     - egress-gateway
>   tls:
>     - match:
>         - gateways: [mesh]
>           port: 443
>           sniHosts: [httpbin.org]
>       route:
>         - destination:
>             host: istio-egress.istio-egress.svc.cluster.local
>             subset: httpbin-org
>             port:
>               number: 443
> ```
>
> Apply it:
>
> ```sh
> kubectl apply -f virtualservice-missing-hop-2.yaml
> ```
>
> Then check the result:
>
> ```sh
> call_external
> log_hop2_egress
> ```
>
> Expect `000 exit=35` — the TLS handshake fails — and no new access-log line on the gateway for this request. When "via egress" breaks, check that **both** rules exist, and that the second one uses `gateways: [<egress gateway>]`.

Restore the working object again with `kubectl apply -f virtualservice-httpbin-org-via-egress.yaml`.

**The `DestinationRule` missing.** Delete it while the `VirtualService` still points at its subset, and hop 1 has no cluster to send to. You get the same `NC` ("no cluster") failure as in section 010:

```sh
kubectl delete -f destinationrule-egress-gateway.yaml
call_external            # 000  exit=35
log_hop1_sidecar         # "- - -" 0 NC ...   ← subset httpbin-org not found
```

Apply it:

```sh
kubectl apply -f destinationrule-egress-gateway.yaml
```

## Restricting who may use the path

Stage 1 is an ordinary mesh-side rule, so it can match on ordinary things. That includes **`sourceLabels`**, which checks the labels of the *calling* workload — which spaceship sent the signal. In the plain-HTTP shape from Part 2:

```yaml
- match:
    - port: 80
      sourceLabels:
        app: tester
  route:
    - destination:
        host: istio-egressgateway.istio-system.svc.cluster.local
        subset: httpbin
        port:
          number: 80
```

Now only pods labelled `app: tester` are routed through the gateway. The graded lab for this module asks for the same thing, with its own label.

> [!WARNING]
> **Do not add `gateways: [mesh]` to that match.** It is the obvious thing to
> write — stage 2 names its gateway, so stage 1 ought to name `mesh` — and on
> Istio 1.30.5 it silently disables the `sourceLabels` predicate: every sidecar
> in the mesh then gets the diverting route, including the workloads you meant
> to exclude. Check it the way you would check any routing claim, by dumping a
> proxy that should *not* have been diverted (here in the graded lab's namespace):
>
> ```sh
> istioctl proxy-config routes deploy/other-client -n egwgw-demo --name 8080
> ```
>
> Leaving `gateways` off the match costs nothing here. The rule still cannot fire
> on the gateway itself, because the gateway pod does not carry the label the
> match requires.

Be precise about what that achieves. `sourceLabels` narrows **the route, not the permission**. A spaceship that does not match simply takes the *direct* path instead. It is not blocked, it is un-diverted. On an `ALLOW_ANY` mesh it still reaches the internet, just without the audit trail. You saw the same effect with `mesh` missing above: a `200`, and no line on the gateway.

To make the gateway a genuine control you need three things together:

| Layer | Object | Provides |
| --- | --- | --- |
| The route | this `VirtualService` (optionally with `sourceLabels`) | who goes via the gateway |
| The permission | `REGISTRY_ONLY` (section 070) | nothing unregistered leaves at all |
| The enforcement | `AuthorizationPolicy` on the gateway, plus a `NetworkPolicy` | which identities the gateway will serve, and no direct path out of the cluster |

With only the first, you have a convention. With all three, you have egress control.

## The trade-off

Worth being able to state in both directions, because an exam question may ask for the reasoning rather than the YAML.

**You gain:**

- One auditable exit point, with caller attribution, instead of a log line in whichever sidecar happened to send it.
- A single source address partners can allow-list, instead of every node's address.
- One place to apply policy, monitoring and rate limits to all outbound traffic.
- A natural home for client certificates — which is module 2, and the strongest argument of the four.

**You pay:**

- An extra network hop on every external call, with its latency.
- A component on the **critical path** for outgoing signals. It needs capacity, monitoring, and enough replicas so it does not become your Death Star: huge and important, with one weak spot that takes down every signal leaving the solar system.
- More configuration per external host: four objects instead of one.

The honest summary: for a cluster with a handful of external dependencies and no compliance requirement, section 070's sidecar-direct approach is simpler and fine. The gateway earns its place when you need the audit trail, the fixed source address, or the certificate consolidation.

## Common pitfalls

> [!WARNING]
> **Expecting the gateway to intercept traffic.** It does nothing until a `VirtualService` routes traffic to it. A running egress gateway pod proves nothing.
>
> **Trusting a `200`.** With `mesh` missing from `gateways`, calls still succeed — straight out, past the gateway. Check hop 1 in the sidecar's log.
>
> **Forgetting hop 2.** The gateway receives the traffic and has no route onward; the client sees a failed TLS handshake (`000 exit=35`).
>
> **Putting an internal hostname in the `Gateway`'s `servers[].hosts`.** It must be the external host the gateway will serve — read the object from the gateway's point of view.
>
> **Getting the two `match.gateways` values backwards.** `mesh` is the sidecar stage, the gateway name is the gateway stage. Swapped, traffic loops or never leaves.
>
> **Forgetting the `ServiceEntry`.** Without the host in the registry there is nothing for either stage to route.
>
> **Deleting the empty-subset `DestinationRule`.** It is a naming device, but hop 1 names its subset — without it, `NC`.
>
> **Believing the gateway is enforced.** Unless `REGISTRY_ONLY`, an `AuthorizationPolicy` and a `NetworkPolicy` prevent it, a pod can still make a direct outbound connection. `sourceLabels` narrows the route, not the permission.
>
> **Counting gateway log lines without a baseline.** The log accumulates across runs; look at the newest line, or count before and after.

> *`sourceLabels` decides who takes the egress path, not who may leave — an un-diverted workload still goes direct.*

## Exam cheat sheet

```yaml
# ServiceEntry: hosts [httpbin.org], port 443 protocol TLS, MESH_EXTERNAL, DNS
# Gateway (egress)
spec:
  selector: {istio: egress}               # demo profile (istioctl): istio: egressgateway
  servers:
  - port: {number: 443, name: tls, protocol: TLS}
    hosts: [httpbin.org]
    tls: {mode: PASSTHROUGH}
# DestinationRule: host istio-egress.istio-egress.svc.cluster.local, subsets [{name: httpbin-org}]
# VirtualService
spec:
  hosts: [httpbin.org]
  gateways: [mesh, egress-gateway]
  tls:
  - match: [{gateways: [mesh], port: 443, sniHosts: [httpbin.org]}]
    route: [{destination: {host: istio-egress.istio-egress.svc.cluster.local, subset: httpbin-org, port: {number: 443}}}]
  - match: [{gateways: [egress-gateway], port: 443, sniHosts: [httpbin.org]}]
    route: [{destination: {host: httpbin.org, port: {number: 443}}}]
```

- HTTPS passthrough → `tls:` routes with `sniHosts`, not `http:`. Plain HTTP → `http:` routes matched on `port`.
- Hop 1 goes to the **egress gateway Service** (full name), hop 2 to the external host.
- Apply order: `ServiceEntry` → `Gateway` → `DestinationRule` → `VirtualService`.
- An egress gateway does not **force** traffic on its own: add `REGISTRY_ONLY` and a `NetworkPolicy`.
