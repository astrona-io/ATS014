# The Five-Step Chain

> Prerequisite: [the module landing page](./course.md). Next: [Where The `DestinationRule` Attaches](./course-02-where-the-destinationrule-attaches.md).

Five steps, each owned by one object. Two of them are where every mistake in this module lives, so it is worth walking the whole path before writing anything.

## The path

```text
  1. app          calls http://httpbin.org/get                   plain HTTP, port 80
                       │
  2. sidecar      matches gateways:[mesh], forwards to the        VirtualService, stage 1
                  egress gateway Service on port 80
                       │
  3. gateway      accepts it for host httpbin.org on port 80      Gateway listener
                       │
  4. gateway      routes it to httpbin.org on port 443            VirtualService, stage 2
                       │
  5. gateway      originates TLS to port 443                      DestinationRule on httpbin.org
                       ▼
                  external service, over HTTPS
```

Compare that with section 070 module 2's three-step version, where the sidecar did steps 3 to 5 itself. Everything is the same except that the work has moved one hop outward.

## Step 4 — the route targets 443, the listener stays on 80

This is the first place people go wrong, because the two port numbers on the gateway look inconsistent.

They are not. They describe different directions:

| | Port | What it is |
| --- | --- | --- |
| `Gateway.servers[].port` | **80** | the port the gateway **accepts** traffic on, from inside the cluster |
| Stage 2's `destination.port` | **443** | the port the gateway **sends** traffic to, outside the cluster |

The gateway is a proxy: it receives on one port and sends on another. Route step 4 to port 80 of the external host and the gateway faithfully forwards plaintext to an HTTPS endpoint, which fails — and the failure looks like a TLS problem when it is a routing one.

## Step 5 — the `DestinationRule` targets the external host

This is the second, and it is the more interesting mistake because it follows from a rule you already know.

The `DestinationRule` that originates TLS names **`httpbin.org`** — the external host — **not** the gateway's own Service:

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: originate-tls-for-httpbin
  namespace: egwtls-demo
spec:
  host: httpbin.org                # ← the EXTERNAL host
  trafficPolicy:
    portLevelSettings:
      - port:
          number: 443
        tls:
          mode: SIMPLE
          sni: httpbin.org
```

The reason is section 030's rule: **traffic policy attaches to a destination and is applied by whichever proxy is calling it.** Since the gateway is the proxy calling `httpbin.org`, the gateway is where this policy takes effect.

Put it on `istio-egressgateway.istio-system.svc.cluster.local` instead and nothing originates — because that is the policy for calls *to the gateway*, which is the sidecar's leg, and that leg is plain HTTP by design.

So this object is byte-for-byte the same as section 070 module 2's, applied by a different proxy because a different proxy is making the call. That is the whole difference between the two modules.

## The `ServiceEntry` needs both ports again

Same reason as section 070 module 2: port 80 is where the traffic arrives from the sidecar, port 443 is where it goes.

```yaml
ports:
  - number: 80
    name: http
    protocol: HTTP
  - number: 443
    name: https
    protocol: HTTPS
```

Declare only 443 and stage 2 has no port-80 entry to start from.

## The five objects

| # | Object | Job |
| --- | --- | --- |
| 1 | `ServiceEntry` | the external host in the registry, with ports 80 and 443 |
| 2 | `Gateway` | a listener on the egress gateway, port 80, for the external hostname |
| 3 | `DestinationRule` on the **gateway Service** | the empty `partner`-style subset, so stage 1 can name a cluster |
| 4 | `VirtualService` | two stages: sidecar → gateway, gateway → external host **on 443** |
| 5 | `DestinationRule` on the **external host** | `tls.mode: SIMPLE` under `portLevelSettings` for 443 |

Two `DestinationRule` objects pointing at two different hosts, doing two unrelated jobs. Keeping them apart is most of the work.

> [!TIP]
> **Try it — the whole chain in one apply**
>
> ```sh
> kubectl apply -f - <<'EOF'
> apiVersion: networking.istio.io/v1
> kind: ServiceEntry
> metadata:
>   name: httpbin-ext
>   namespace: egwtls-demo
> spec:
>   hosts:
>     - httpbin.org
>   ports:
>     - number: 80
>       name: http
>       protocol: HTTP
>     - number: 443
>       name: https
>       protocol: HTTPS
>   location: MESH_EXTERNAL
>   resolution: DNS
> ---
> apiVersion: networking.istio.io/v1
> kind: Gateway
> metadata:
>   name: istio-egressgateway
>   namespace: egwtls-demo
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
>   namespace: egwtls-demo
> spec:
>   host: istio-egressgateway.istio-system.svc.cluster.local
>   subsets:
>     - name: httpbin
> ---
> apiVersion: networking.istio.io/v1
> kind: VirtualService
> metadata:
>   name: httpbin-through-egress
>   namespace: egwtls-demo
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
>               number: 443
> ---
> apiVersion: networking.istio.io/v1
> kind: DestinationRule
> metadata:
>   name: originate-tls-for-httpbin
>   namespace: egwtls-demo
> spec:
>   host: httpbin.org
>   trafficPolicy:
>     portLevelSettings:
>       - port:
>           number: 443
>         tls:
>           mode: SIMPLE
>           sni: httpbin.org
> EOF
> sleep 4
> kubectl -n egwtls-demo exec deploy/tester -- \
>   curl -s -o /dev/null -w 'http:// call: %{http_code}\n' --max-time 20 http://httpbin.org/get
> ```
>
> Expect something like:
>
> ```text
> http:// call: 200
> ```
>
> A plain `http://` call from an application that knows nothing about any of this, answered over a TLS connection made two hops away. As in module 1, the response alone proves nothing — Part 2 is the evidence.

> *The gateway receives on 80 and sends on 443 — the two port numbers are the two directions, not an inconsistency.*

## Reference

- [Egress gateway TLS origination](https://istio.io/latest/docs/tasks/traffic-management/egress/egress-gateway-tls-origination/) — the upstream walkthrough for this exact chain.
- [ClientTLSSettings API](https://istio.io/latest/docs/reference/config/networking/destination-rule/#ClientTLSSettings) — `mode`, `sni`, `credentialName`.
- [Egress TLS origination](https://istio.io/latest/docs/tasks/traffic-management/egress/egress-tls-origination/) — the sidecar version, for the comparison.
- [Egress gateways](https://istio.io/latest/docs/tasks/traffic-management/egress/egress-gateway/) — module 1's two-stage routing.
