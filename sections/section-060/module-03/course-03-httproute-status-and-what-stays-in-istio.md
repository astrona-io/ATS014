# Part 3 — `HTTPRoute`, Status And What Stays In Istio

> Prerequisite: [Part 2 — A Gateway That Creates Its Own Data Plane](./course-02-a-gateway-that-creates-its-own-data-plane.md). Next: [the module landing page](./course.md).

The routing half, the status conditions that make this API far easier to debug than `Ingress`, and an explicit line around what the Gateway API does not cover.

## Translating a `VirtualService`

| `VirtualService` | `HTTPRoute` |
| --- | --- |
| `gateways: [name]` | `parentRefs: [{name: ...}]` |
| `hosts` | `hostnames` |
| `http[].match` | `rules[].matches` |
| `http[].match[].uri.prefix` | `matches[].path` with `type: PathPrefix` |
| `http[].route[].destination` | `rules[].backendRefs` |
| `weight` | `weight` — same idea, same place |
| header add / remove / rewrite | `rules[].filters` |
| `redirect`, `rewrite` | `rules[].filters` of type `RequestRedirect`, `URLRewrite` |

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: booking
  namespace: gwapi-demo
spec:
  parentRefs:
    - name: booking-gateway
  hostnames:
    - booking.ica.local
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /book
      backendRefs:
        - name: booking-service
          port: 80
```

Three differences worth naming:

- **`backendRefs` names a Kubernetes Service directly** — no Istio host string, no subset. Subsets still come from a `DestinationRule` alongside.
- **`parentRefs` is a list**, so one route can attach to several Gateways. That is how you serve the same application on an internal and an external gateway without duplicating the routing.
- **`path.type` is `PathPrefix`, `Exact` or `RegularExpression`** — and `PathPrefix` is **element-wise**, like `Ingress`'s `pathType: Prefix` and unlike Istio's `uri.prefix`. The same trap as module 2.

> [!TIP]
> **Try it — attach a route and send a request**
>
> ```sh
> kubectl apply -f - <<'EOF'
> apiVersion: gateway.networking.k8s.io/v1
> kind: HTTPRoute
> metadata:
>   name: booking
>   namespace: gwapi-demo
> spec:
>   parentRefs:
>     - name: booking-gateway
>   hostnames:
>     - booking.ica.local
>   rules:
>     - matches:
>         - path:
>             type: PathPrefix
>             value: /book
>       backendRefs:
>         - name: booking-service
>           port: 80
> EOF
> kubectl -n gwapi-demo port-forward svc/booking-gateway-istio 8080:80 >/dev/null 2>&1 &
> sleep 3
> curl -s -o /dev/null -w '%{http_code}\n' -H "Host: booking.ica.local" http://localhost:8080/book
> kubectl -n gwapi-demo get destinationrule,virtualservice 2>/dev/null
> ```
>
> Expect something like:
>
> ```text
> httproute.gateway.networking.k8s.io/booking created
> 200
> No resources found in gwapi-demo namespace.
> ```
>
> Same `Host` header discipline as the other two modules — the hostname is a routing key, not a DNS lookup. And there is no Istio networking object in the namespace at all.

## Status conditions

This is the biggest practical improvement over `Ingress`, which had essentially no status. Both objects report structured conditions, and reading them replaces most guesswork.

On a **`Gateway`**:

| Condition | `True` means | `False` usually means |
| --- | --- | --- |
| `Accepted` | the configuration is valid and this controller claimed it | bad `gatewayClassName`, or an invalid listener |
| `Programmed` | the data plane exists and is ready | the proxy Deployment has not come up |

`Accepted=True, Programmed=False` is a precise and useful statement: your YAML is fine, the infrastructure is not ready yet.

On an **`HTTPRoute`**, status is **per parent**, under `status.parents[]`:

| Condition | `True` means | `False` usually means |
| --- | --- | --- |
| `Accepted` | the parent Gateway allowed this attachment | `allowedRoutes` does not permit this namespace, or the hostnames do not overlap the listener's |
| `ResolvedRefs` | every `backendRefs` target was found | a Service name or port is wrong |

> [!TIP]
> **Try it — read both objects' conditions**
>
> ```sh
> kubectl -n gwapi-demo get gateway booking-gateway \
>   -o jsonpath='{range .status.conditions[*]}{.type}={.status} {end}{"\n"}'
> kubectl -n gwapi-demo get httproute booking \
>   -o jsonpath='{range .status.parents[0].conditions[*]}{.type}={.status} {end}{"\n"}'
> ```
>
> Expect something like:
>
> ```text
> Accepted=True Programmed=True
> Accepted=True ResolvedRefs=True
> ```
>
> Four `True` values is a fully working chain: the Gateway is valid and has a running proxy, the route was allowed to attach, and its backend resolves. When something breaks, the one reading `False` tells you which half to look at — and `kubectl describe` on that object prints the message explaining it.

Breaking one deliberately is worth doing once, because it is the fastest way to learn the diagnostic:

> [!TIP]
> **Try it — a backend that does not exist**
>
> ```sh
> kubectl -n gwapi-demo patch httproute booking --type merge \
>   -p '{"spec":{"rules":[{"matches":[{"path":{"type":"PathPrefix","value":"/book"}}],"backendRefs":[{"name":"no-such-service","port":80}]}]}}'
> sleep 3
> kubectl -n gwapi-demo get httproute booking \
>   -o jsonpath='{range .status.parents[0].conditions[*]}{.type}={.status} ({.reason}) {end}{"\n"}'
> ```
>
> Expect something like:
>
> ```text
> Accepted=True (Accepted) ResolvedRefs=False (BackendNotFound)
> ```
>
> `Accepted=True` — the Gateway was happy to take the route. `ResolvedRefs=False` with reason `BackendNotFound` — the backend is not there. Two conditions, two different problems, named precisely. Compare with `Ingress`, where this situation produces a 503 and nothing else. Restore `booking-service` before moving on.

## Weights and filters

Traffic shifting is native here — `backendRefs` is a list and each entry takes a `weight`:

```yaml
rules:
  - backendRefs:
      - name: booking-service
        port: 80
        weight: 90
      - name: booking-service-v2
        port: 80
        weight: 10
```

Unlike `Ingress`, this is a real field in the portable API. Header manipulation, redirects and URL rewriting are likewise available through `rules[].filters`:

```yaml
filters:
  - type: RequestHeaderModifier
    requestHeaderModifier:
      add:
        - name: x-canary
          value: "true"
```

## What stays an Istio object

The line to be able to draw:

| Concern | Gateway API | Istio |
| --- | --- | --- |
| Host / path / header / method matching | ✅ `HTTPRoute` | |
| Traffic splitting by weight | ✅ `backendRefs[].weight` | |
| Header manipulation, redirect, rewrite | ✅ `filters` | |
| Subsets over pod labels | | **`DestinationRule`** |
| Load balancer policy, session affinity | | **`DestinationRule`** |
| Connection pools, outlier detection | | **`DestinationRule`** |
| Retries, timeouts | partial — some fields exist | **`VirtualService`** for the full set |
| Mirroring | ✅ `RequestMirror` filter | `VirtualService` also |
| Fault injection | | **`VirtualService`** |

The important part: **a `DestinationRule` applies to a host however the request was routed to it.** Client-side policy is attached to the destination, not to the route, so everything from sections 030 and 040 continues to work unchanged alongside an `HTTPRoute`. You do not choose between them.

## Common pitfalls

> [!WARNING]
> **Missing Gateway API CRDs.** Every apply fails with `no matches for kind`. It is not an Istio error; install the CRDs.
>
> **Looking for the gateway pod in `istio-system`.** Gateway API deploys it in the `Gateway`'s own namespace as `<gateway-name>-istio`.
>
> **An `HTTPRoute` in another namespace with `from: Same`.** It stays `Accepted=False`. This API is deny-by-default, unlike the older two.
>
> **Confusing the two `Gateway` kinds.** Check the `apiVersion` before reading any example. `networking.istio.io` has a `selector` and configures an existing pod; `gateway.networking.k8s.io` has a `gatewayClassName` and creates one.
>
> **Ignoring the status conditions.** They name the failure precisely. `kubectl describe` on the Gateway or the route beats rereading YAML.
>
> **Reading `PathPrefix` as a string prefix.** It is element-wise, like `Ingress` and unlike Istio's `uri.prefix`.
>
> **Expecting `DestinationRule` behaviour from `backendRefs`.** It points at a Service. Subsets and client-side policy remain Istio objects.
>
> **Port-forwarding to `istio-ingressgateway`.** That is module 1's proxy and it knows nothing about your `HTTPRoute`.

> *`Accepted` is about attachment and `ResolvedRefs` is about backends — the condition reading `False` tells you which half of the configuration to look at.*

## Reference

- [Gateway API: HTTPRoute](https://gateway-api.sigs.k8s.io/api-types/httproute/) — matches, filters, `backendRefs` and weights.
- [Istio Kubernetes Gateway API task](https://istio.io/latest/docs/tasks/traffic-management/ingress/gateway-api/) — Istio's implementation, including what is and is not supported.
- [Gateway API status and conditions](https://gateway-api.sigs.k8s.io/geps/gep-1364/) — the condition model the diagnostics above rely on.
- [DestinationRule API](https://istio.io/latest/docs/reference/config/networking/destination-rule/) — the object that keeps working alongside an `HTTPRoute`.
