# Restricting, Proving And The Trade-Off

> Prerequisite: [The Two-Stage `VirtualService`](./course-02-the-two-stage-virtualservice.md). Next: [the module landing page](./course.md).

The configuration works and looks identical to not having it. This part is the evidence, the way to narrow who uses the path, and an honest account of what the arrangement costs.

## Proving the hop happened

The gateway's own access log is the direct evidence — and it is also the reason the whole arrangement exists.

> [!TIP]
> **Try it — the request in the gateway's own log**
>
> ```sh
> BEFORE=$(kubectl -n istio-system logs deploy/istio-egressgateway --tail=-1 2>/dev/null | grep -c httpbin.org)
> kubectl -n egwgw-demo exec deploy/tester -- \
>   curl -s -o /dev/null --max-time 15 http://httpbin.org/get
> sleep 2
> AFTER=$(kubectl -n istio-system logs deploy/istio-egressgateway --tail=-1 2>/dev/null | grep -c httpbin.org)
> echo "gateway log lines for httpbin.org: +$((AFTER - BEFORE))"
> kubectl -n istio-system logs deploy/istio-egressgateway --tail=5 | grep httpbin.org | tail -1
> ```
>
> Expect something like:
>
> ```text
> gateway log lines for httpbin.org: +1
> [2026-09-27T13:22:41.006Z] "GET /get HTTP/1.1" 200 - via_upstream - "-" 0 3428 214 213 "10.244.0.28" "curl/8.5.0" "6f2c..." "httpbin.org" "34.194.82.45:80" outbound|80||httpbin.org ...
> ```
>
> Compare with the `0` from Part 1. The gateway is now in the path, and **this log — one place, not every sidecar — is the audit trail the whole arrangement exists to produce.** Note the `"10.244.0.28"` field: that is the calling pod, so you get attribution as well as a record.

Taking a `BEFORE` count matters here for the same reason as section 020's mirroring checkpoint: the log accumulates, and a raw count tells you about every run you have ever done.

## Restricting who may use the path

Stage 1 is an ordinary mesh-side rule, so it can match on ordinary things — including **`sourceLabels`**, which selects by the labels of the *calling* workload:

```yaml
- match:
    - gateways: [mesh]
      port: 80
      sourceLabels:
        app: tester
  route:
    - destination:
        host: istio-egressgateway.istio-system.svc.cluster.local
        subset: httpbin
        port:
          number: 80
```

Now only pods labelled `app: tester` are routed through the gateway.

Be precise about what that achieves. `sourceLabels` narrows **the route, not the permission**. A workload that does not match simply takes the *direct* path instead — it is not blocked, it is un-diverted. On an `ALLOW_ANY` mesh that means it still reaches the internet, just without the audit trail.

To make the gateway a genuine control you need three things together:

| Layer | Object | Provides |
| --- | --- | --- |
| The route | this `VirtualService` with `sourceLabels` | who goes via the gateway |
| The permission | `REGISTRY_ONLY` (section 070) | nothing unregistered leaves at all |
| The enforcement | `AuthorizationPolicy` on the gateway | which identities the gateway will serve |

With only the first, you have a convention. With all three, you have egress control.

> [!TIP]
> **Try it — narrow the path and see what "un-diverted" means**
>
> ```sh
> kubectl -n egwgw-demo patch virtualservice httpbin-through-egress --type json -p '[
>   {"op":"add","path":"/spec/http/0/match/0/sourceLabels","value":{"app":"nobody"}}
> ]'
> sleep 3
> BEFORE=$(kubectl -n istio-system logs deploy/istio-egressgateway --tail=-1 2>/dev/null | grep -c httpbin.org)
> kubectl -n egwgw-demo exec deploy/tester -- \
>   curl -s -o /dev/null -w 'call: %{http_code}\n' --max-time 15 http://httpbin.org/get
> sleep 2
> AFTER=$(kubectl -n istio-system logs deploy/istio-egressgateway --tail=-1 2>/dev/null | grep -c httpbin.org)
> echo "gateway log lines: +$((AFTER - BEFORE))"
> ```
>
> Expect something like:
>
> ```text
> call: 200
> gateway log lines: +0
> ```
>
> The call **still succeeds** — and the gateway saw none of it. `tester` does not match `app: nobody`, so stage 1 did not apply and the sidecar took the direct path. That is the difference between a route and a wall, in one experiment. Revert the patch (`"op":"remove"` on the same path) before moving on.

## The trade-off

Worth being able to state in both directions, because an exam question may ask for the reasoning rather than the YAML.

**You gain:**

- One auditable exit point, with caller attribution, instead of a log line in whichever sidecar happened to send it.
- A single source address partners can allow-list, instead of every node's address.
- One place to apply policy, monitoring and rate limits to all outbound traffic.
- A natural home for client certificates — which is module 2, and the strongest argument of the four.

**You pay:**

- An extra network hop on every external call, with its latency.
- A component on the **critical path** for outbound traffic. It needs capacity, monitoring, and enough replicas that it is not a single point of failure.
- More configuration per external host: four objects instead of one.

The honest summary: for a cluster with a handful of external dependencies and no compliance requirement, section 070's sidecar-direct approach is simpler and fine. The gateway earns its place when you need the audit trail, the fixed source address, or the certificate consolidation.

## Common pitfalls

> [!WARNING]
> **Expecting the gateway to intercept traffic.** It does nothing until a `VirtualService` routes traffic to it. A running egress gateway pod proves nothing.
>
> **Putting an internal hostname in the `Gateway`'s `servers[].hosts`.** It must be the external host the gateway will serve — read the object from the gateway's point of view.
>
> **Getting the two `match.gateways` values backwards.** `mesh` is the sidecar stage, the gateway name is the gateway stage. Swapped, traffic loops or never leaves.
>
> **Omitting `mesh` from the top-level `gateways` list.** Stage 1 is never programmed into sidecars and nothing is diverted.
>
> **Forgetting the `ServiceEntry`.** Without the host in the registry there is nothing for either stage to route.
>
> **Believing the gateway is enforced.** Unless `REGISTRY_ONLY` and an `AuthorizationPolicy` prevent it, a pod can still make a direct outbound connection. `sourceLabels` narrows the route, not the permission.
>
> **Counting gateway log lines without a baseline.** The log accumulates across runs.
>
> **Treating the empty-subset `DestinationRule` as meaningful filtering.** It is a naming device so several external hosts stay distinguishable on one gateway.

> *`sourceLabels` decides who takes the egress path, not who may leave — an un-diverted workload still goes direct.*

## Reference

- [Egress gateways task](https://istio.io/latest/docs/tasks/traffic-management/egress/egress-gateway/) — including the source-label example.
- [Egress gateways and security](https://istio.io/latest/docs/tasks/traffic-management/egress/egress-gateway/#additional-security-considerations) — Istio's own statement that a gateway is not by itself a security boundary.
- [Authorization policy](https://istio.io/latest/docs/reference/config/security/authorization-policy/) — the enforcement layer to pair it with.
- `kubectl -n istio-system logs deploy/istio-egressgateway` — the single audit trail this module buys.
