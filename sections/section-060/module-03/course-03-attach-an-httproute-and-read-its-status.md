# Attach An HTTPRoute And Read Its Status

A Gateway API `Gateway` with no route answers every request with `404`. The `HTTPRoute` is the object that tells the gateway proxy which requests go to which Service. This part attaches one, sends requests through it, and then breaks it on purpose, so you learn to read its status conditions when something is wrong.

The commands below need the `starfleet-gateway` `Gateway` in the `starfleet` namespace, with a listener for `starfleet.example.com`. If `kubectl get gateway -n starfleet` shows nothing, apply your `gateway-starfleet.yaml` again.

## From VirtualService to HTTPRoute

A `VirtualService` is Istio's own routing object: it matches requests and sends them to a destination. If you have written one, most of an `HTTPRoute` will look familiar. The fields have new names, but they do the same jobs:

| `VirtualService` | `HTTPRoute` |
| --- | --- |
| `gateways: [name]` | `parentRefs: [{name: ...}]` |
| `hosts` | `hostnames` |
| `http[].match` | `rules[].matches` |
| `uri.prefix` in a match | `path` with `type: PathPrefix` |
| `http[].route[].destination` | `rules[].backendRefs` |
| `weight` | `weight` on a `backendRefs` entry |
| header changes, `redirect`, `rewrite` | `rules[].filters` |

Three differences are worth knowing. First, `backendRefs` names a Kubernetes Service and a port directly; there is no subset field, so a backend is always a whole Service. Second, `parentRefs` is a list, so one route can attach to several gateways at once. Third, `PathPrefix` matches whole path segments: `/productpage` matches `/productpage` and `/productpage/x`, but not `/productpageX`. Istio's `uri.prefix` would match all three.

## Attach a route to the bridge

The first route sends requests for `/productpage` to the `bridge` Service on port `9080`.

<!-- astrona:playground:renew -->

Save this as `httproute-bridge.yaml`:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: bridge
  namespace: starfleet
spec:
  parentRefs:
  - name: starfleet-gateway
  hostnames:
  - starfleet.example.com
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /productpage
    backendRefs:
    - name: bridge
      port: 9080
```

`parentRefs` names the `Gateway` this route attaches to. `hostnames` must match the listener's host name. `matches` selects the requests, and `backendRefs` names the Service that receives them.

Apply it:

```sh
kubectl apply -f httproute-bridge.yaml
```

Then check the result. Send two requests from the `shuttle` pod through the gateway: one to the bridge page, and one to a path that no rule names:

```sh
kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" \
  -H "Host: starfleet.example.com" http://starfleet-gateway-istio.starfleet/productpage
kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" \
  -H "Host: starfleet.example.com" http://starfleet-gateway-istio.starfleet/reviews/0
```

You should see:

```text
200
404
```

The gateway proxy sent `/productpage` to the `bridge` Service, which answered `200`. The route has no rule for `/reviews/0`, so the proxy answered `404` itself. There is no `VirtualService` anywhere: the `HTTPRoute` alone routes these requests.

## The status conditions of a route

An `HTTPRoute` also reports conditions. It reports them **per parent gateway**, under `status.parents`, because one route can attach to several gateways, and each gateway can accept it or refuse it. Two conditions matter:

| Condition | `True` means | `False` usually means |
| --- | --- | --- |
| `Accepted` | the gateway accepted this route | `allowedRoutes` refuses this namespace, or no listener host name matches the route's `hostnames` |
| `ResolvedRefs` | every `backendRefs` Service was found | a Service name or port is wrong |

`Accepted` is about the gateway side, and `ResolvedRefs` is about the backend side. The condition that reads `False` tells you which half of the route to fix.

Print every condition of the route, with its reason and message:

```sh
kubectl get httproute bridge -n starfleet \
  -o jsonpath='{range .status.parents[*].conditions[*]}{.type}={.status} {.reason}: {.message}{"\n"}{end}'
```

You should see:

```text
Accepted=True Accepted: Route was valid
ResolvedRefs=True ResolvedRefs: All references resolved
```

Both conditions are `True`: the gateway accepted the route, and the `bridge` Service exists. `kubectl describe httproute bridge -n starfleet` shows the same conditions in a longer form.

## Break the backend

A typo in a Service name is the most common route mistake. Keep the broken version in its own file, so you can switch back easily. This route names the Service `brigde` instead of `bridge`.

Save this as `httproute-bridge-typo.yaml`:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: bridge
  namespace: starfleet
spec:
  parentRefs:
  - name: starfleet-gateway
  hostnames:
  - starfleet.example.com
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /productpage
    backendRefs:
    - name: brigde
      port: 9080
```

Apply it:

```sh
kubectl apply -f httproute-bridge-typo.yaml
```

Then check the result. Read the status, send a request, and read the gateway proxy's access log:

```sh
kubectl get httproute bridge -n starfleet \
  -o jsonpath='{range .status.parents[*].conditions[*]}{.type}={.status} {.reason}: {.message}{"\n"}{end}'
kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" \
  -H "Host: starfleet.example.com" http://starfleet-gateway-istio.starfleet/productpage
kubectl logs -n starfleet deploy/starfleet-gateway-istio --tail=1
```

You should see this (the log line is shortened):

```text
Accepted=True Accepted: Route was valid
ResolvedRefs=False BackendNotFound: backend(brigde.starfleet.svc.cluster.local) not found
500
[2026-10-08T22:28:51.706Z] "GET /productpage HTTP/1.1" 500 NC cluster_not_found ...
```

The gateway still accepts the route, so `Accepted` stays `True`. But `ResolvedRefs` is `False` with the reason `BackendNotFound`, and the message names the missing Service. The gateway proxy answers `500` with the response flag `NC`, short for "no cluster": Envoy has no upstream cluster, that is no group of endpoints, to send the request to. `istioctl analyze -n starfleet` reports the same problem as `IST0171`, a warning that a condition is `False`.

Put the correct route back:

```sh
kubectl apply -f httproute-bridge.yaml
```

## Name a gateway that does not exist

A typo in `parentRefs` fails more quietly than a typo in `backendRefs`. To see it, change only the gateway's name in the route, with a short `kubectl patch`:

```sh
kubectl patch httproute bridge -n starfleet --type json \
  -p '[{"op":"replace","path":"/spec/parentRefs/0/name","value":"starfleet-gate"}]'
```

Then read the route's status, ask the `Gateway` how many routes its listener holds, and send a request:

```sh
kubectl get httproute bridge -n starfleet -o jsonpath='{.status.parents}{"\n"}'
kubectl get gateway starfleet-gateway -n starfleet -o jsonpath='{.status.listeners[0].attachedRoutes}{"\n"}'
kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" \
  -H "Host: starfleet.example.com" http://starfleet-gateway-istio.starfleet/productpage
```

You should see:

```text
[]
0
404
```

The route has no status at all: the `status.parents` list is empty. No `Gateway` called `starfleet-gate` exists, so no controller writes a status for the route, not even `Accepted=False`. The real `Gateway` holds `0` routes, and its proxy answers `404 NR`. An empty `status.parents` always means "check the name and namespace in `parentRefs`".

Put the correct route back:

```sh
kubectl apply -f httproute-bridge.yaml
```

## Weights and filters

`backendRefs` is a list, and each entry takes a `weight`, so traffic shifting is a normal field. This piece of an `HTTPRoute` sends 90% of requests to one Service and 10% to another. It is only an example, and you do not apply it:

```yaml
  rules:
  - backendRefs:
    - name: scout-v1
      port: 9080
      weight: 90
    - name: scout-v2
      port: 9080
      weight: 10
```

Each weight goes to a Service, so every version needs its own Service. Your playground has one `scout` Service for all three versions, so this split does not work there.

Header changes, redirects and path rewrites go in `filters`. For example, a `RequestHeaderModifier` filter adds a header to every request that matches the rule:

```yaml
    filters:
    - type: RequestHeaderModifier
      requestHeaderModifier:
        add:
        - name: x-canary
          value: "true"
```

## What stays an Istio object

The Gateway API covers how requests are matched and where they go. Some jobs it does not cover, and for those you still write Istio objects. A `DestinationRule` is Istio's object for traffic policy at the destination Service, such as subsets, load balancing and connection pools.

| Job | Gateway API | Istio |
| --- | --- | --- |
| Match on host, path, header, method | `HTTPRoute` | |
| Split traffic by weight | `backendRefs[].weight` | |
| Change headers, redirect, rewrite | `filters` | |
| Subsets over pod labels | | `DestinationRule` |
| Load balancing, session affinity | | `DestinationRule` |
| Connection pools, outlier detection | | `DestinationRule` |
| Retries and timeouts | some fields | `VirtualService` has the full set |
| Fault injection | | `VirtualService` |

A `DestinationRule` belongs to the destination Service, not to the route. Its policy applies to every request for that Service, whichever object routed the request there. So a `DestinationRule` for `bridge` still applies when an `HTTPRoute` sends the request, and you do not have to choose between the two.

You can now attach an `HTTPRoute`, send requests through it, and use its `Accepted` and `ResolvedRefs` conditions to decide whether the gateway side or the backend side is wrong. Every route so far lived in the same namespace as the `Gateway`. The open question is what happens when a route in another namespace wants to use the same gateway.

## Common pitfalls

> [!WARNING]
> - **A typo in `backendRefs`.** The route stays `Accepted=True`, but shows `ResolvedRefs=False BackendNotFound`, and requests get `500 NC`.
> - **A typo in `parentRefs`.** No gateway writes a status for the route, so it has no status at all. An empty `status.parents` points at `parentRefs`.
> - **Ignoring the status.** The condition that reads `False` names the problem. Read it before you read the YAML again.
> - **Reading `PathPrefix` as a text prefix.** It matches whole path segments, unlike Istio's `uri.prefix`.
> - **Looking for subsets in `backendRefs`.** A backend is a Service. Subsets and traffic policy stay in a `DestinationRule`.

## Your mission: Fix Two Broken HTTPRoutes From Their Status Conditions Lab

You can now read an `HTTPRoute`'s status conditions and tell from them what is wrong. The mission gives you a working `Gateway` and two `HTTPRoute` objects that are broken in two different ways, and asks you to fix both without changing the `Gateway`.

The lab runs on its own cluster, so first pause your playground. Nothing in it is lost:

```sh
astrona stop ats-014-playground-060-03
```

Then start the lab. The task is on the next page; solve it on your own first:

```sh
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-060/module-03/labs/lab-03
```

When you think you are done, send it for grading:

```sh
astrona submit -c sections/section-060/module-03/labs/lab-03
```

When the lab is done, remove it and start your playground again:

```sh
astrona destroy ats-014-lab-060-03-03
astrona start ats-014-playground-060-03
```
