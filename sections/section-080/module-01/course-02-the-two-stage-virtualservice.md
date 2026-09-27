# Part 2 — The Two-Stage `VirtualService`

> Prerequisite: [Part 1 — A Gateway That Carries Nothing](./course-01-a-gateway-that-carries-nothing.md). Next: [Part 3 — Restricting, Proving And The Trade-Off](./course-03-restricting-proving-and-the-trade-off.md).

One object, two rule sets, two different proxies. This is the shape to memorise, and the `match.gateways` field is what keeps the halves apart.

## One document, two places

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: httpbin-through-egress
  namespace: egwgw-demo
spec:
  hosts:
    - httpbin.org
  gateways:
    - mesh                       # ← the sidecars
    - istio-egressgateway        # ← the gateway
  http:
    # Stage 1 — runs in the SIDECARS: send it to the gateway
    - match:
        - gateways: [mesh]
          port: 80
      route:
        - destination:
            host: istio-egressgateway.istio-system.svc.cluster.local
            subset: httpbin
            port:
              number: 80
    # Stage 2 — runs on the GATEWAY: send it to the real host
    - match:
        - gateways: [istio-egressgateway]
          port: 80
      route:
        - destination:
            host: httpbin.org
            port:
              number: 80
```

The journey, with the owning proxy named at each step:

```text
  app ──► tester's sidecar            stage 1 runs here
             │  route → istio-egressgateway.istio-system.svc
             ▼
        egress gateway pod            stage 2 runs here
             │  route → httpbin.org
             ▼
        httpbin.org
```

## `mesh` — the name you have been using all along

`mesh` is a **reserved gateway name meaning "all sidecars"**. You met it implicitly in section 060: a `VirtualService` with no `gateways` field applies to `mesh`.

Here it is written out explicitly so it can sit beside a real gateway name in the same `gateways` list, and so each `http` rule can say which of the two it belongs to.

That is the mechanism that makes one document configure two different proxies:

| `match.gateways` | The rule is programmed into | It says |
| --- | --- | --- |
| `[mesh]` | every sidecar | "do not go direct — go to the gateway" |
| `[istio-egressgateway]` | the gateway proxy | "you are the gateway; go to the real host" |

Get those two backwards and the traffic either loops — the gateway told to send to the gateway — or never diverts, because the sidecar rule was programmed onto the gateway where no application traffic arrives.

The top-level `gateways` list must name **both**. Omit `mesh` and stage 1 is never programmed into sidecars, so nothing is ever diverted; omit the gateway name and stage 2 never reaches the gateway, so it has no idea what to do with the traffic it receives.

## The `ServiceEntry` is still required

Nothing here replaces section 070. `httpbin.org` must be in the registry, or neither stage has a host to route. On a `REGISTRY_ONLY` mesh it is also what permits the traffic at all.

> [!TIP]
> **Try it — route the external host through the gateway**
>
> ```sh
> kubectl apply -f - <<'EOF'
> apiVersion: networking.istio.io/v1
> kind: ServiceEntry
> metadata:
>   name: httpbin-ext
>   namespace: egwgw-demo
> spec:
>   hosts:
>     - httpbin.org
>   ports:
>     - number: 80
>       name: http
>       protocol: HTTP
>   location: MESH_EXTERNAL
>   resolution: DNS
> ---
> apiVersion: networking.istio.io/v1
> kind: Gateway
> metadata:
>   name: istio-egressgateway
>   namespace: egwgw-demo
> spec:
>   selector:
>     istio: egressgateway
>   servers:
>     - port:
>         number: 80
>         name: http
>         protocol: HTTP
>       hosts:
>         - httpbin.org
> ---
> apiVersion: networking.istio.io/v1
> kind: DestinationRule
> metadata:
>   name: egressgateway-for-httpbin
>   namespace: egwgw-demo
> spec:
>   host: istio-egressgateway.istio-system.svc.cluster.local
>   subsets:
>     - name: httpbin
> ---
> apiVersion: networking.istio.io/v1
> kind: VirtualService
> metadata:
>   name: httpbin-through-egress
>   namespace: egwgw-demo
> spec:
>   hosts:
>     - httpbin.org
>   gateways:
>     - mesh
>     - istio-egressgateway
>   http:
>     - match:
>         - gateways: [mesh]
>           port: 80
>       route:
>         - destination:
>             host: istio-egressgateway.istio-system.svc.cluster.local
>             subset: httpbin
>             port:
>               number: 80
>     - match:
>         - gateways: [istio-egressgateway]
>           port: 80
>       route:
>         - destination:
>             host: httpbin.org
>             port:
>               number: 80
> EOF
> sleep 3
> kubectl -n egwgw-demo exec deploy/tester -- \
>   curl -s -o /dev/null -w 'external call: %{http_code}\n' --max-time 15 http://httpbin.org/get
> ```
>
> Expect something like:
>
> ```text
> external call: 200
> ```
>
> The same `200` as before any of this existed. From the application's side nothing changed at all — which is the point, and also why you cannot tell from the response whether the gateway is involved. Part 3 is the proof.

## What the sidecar's route looks like now

The structural change is visible in the sidecar's own configuration: its destination for `httpbin.org` is no longer the internet.

> [!TIP]
> **Try it — the sidecar's route points inward**
>
> ```sh
> istioctl proxy-config routes deploy/tester -n egwgw-demo --name 80 -o json \
>   | grep -i '"cluster"' | head -3
> ```
>
> Expect something like:
>
> ```text
> "cluster": "outbound|80|httpbin|istio-egressgateway.istio-system.svc.cluster.local",
> ```
>
> The sidecar's destination for `httpbin.org` is an **in-cluster Service**. The `|httpbin|` in the middle is the subset from the otherwise-pointless `DestinationRule` — the same cluster-naming format from section 020's weighted routing, which is a reminder that none of this is special machinery. Stage 1 did exactly what it said.

> *One `VirtualService`, two rule sets, two proxies — `match.gateways` decides which proxy each rule is programmed into.*

## Reference

- [Egress gateways task](https://istio.io/latest/docs/tasks/traffic-management/egress/egress-gateway/) — the two-stage example in full.
- [VirtualService API](https://istio.io/latest/docs/reference/config/networking/virtual-service/) — the `gateways` field and the reserved `mesh` value.
- [HTTPMatchRequest `gateways`](https://istio.io/latest/docs/reference/config/networking/virtual-service/#HTTPMatchRequest) — per-rule gateway scoping, which is what makes two stages possible.
- `istioctl proxy-config routes <workload> --name 80 -o json` — where stage 1's effect is visible.
