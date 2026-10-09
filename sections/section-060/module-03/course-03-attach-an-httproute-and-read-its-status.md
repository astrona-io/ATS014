# Attach An HTTPRoute And Read Its Status

Astronaut, an open gate with no flight plan answers every signal with `404`. The `HTTPRoute` is the flight plan: it tells the gate which signals go to which Service. In this part you attach one, send signals through it, and learn to read its status lights when something is wrong.

The commands below need the `starfleet-gateway` `Gateway` in the `starfleet` namespace, with a listener for `starfleet.example.com`. If `kubectl get gateway -n starfleet` shows nothing, apply your `gateway-starfleet.yaml` again.

## From VirtualService to HTTPRoute

If you have written an Istio `VirtualService`, most of an `HTTPRoute` will look familiar. The fields have new names, but they do the same jobs:

| `VirtualService` | `HTTPRoute` |
| --- | --- |
| `gateways: [name]` | `parentRefs: [{name: ...}]` |
| `hosts` | `hostnames` |
| `http[].match` | `rules[].matches` |
| `uri.prefix` in a match | `path` with `type: PathPrefix` |
| `http[].route[].destination` | `rules[].backendRefs` |
| `weight` | `weight` on a `backendRefs` entry |
| header changes, `redirect`, `rewrite` | `rules[].filters` |

Three differences are worth knowing:

- **`backendRefs` names a Kubernetes Service and a port directly.** There is no subset field. A backend is a beacon (Service), not a ship class.
- **`parentRefs` is a list.** One route can attach to several gates at once.
- **`PathPrefix` matches whole path parts.** `/productpage` matches `/productpage` and `/productpage/x`, but not `/productpageX`. Istio's `uri.prefix` would match all three.

<!-- astrona:playground:renew -->

### Attach a route to the bridge

Send signals for `/productpage` to the `bridge` Service. Save this as `httproute-bridge.yaml`:

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

`parentRefs` names the gate this route docks at. `hostnames` must fit the listener's host name. `matches` picks the signals, and `backendRefs` says where they fly.

Apply it:

```sh
kubectl apply -f httproute-bridge.yaml
```

Then send two signals through the gate, one to the bridge page and one to a path no rule names:

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

The gate's proxy sent `/productpage` to the bridge, which answered `200`. The route has no rule for `/reviews/0`, so the proxy answered `404` itself. There is no Istio `VirtualService` anywhere: the `HTTPRoute` alone steers these signals.

## The status lights on a route

An `HTTPRoute` also reports conditions. It reports them **per gate**, under `status.parents`, because one route can dock at several gates, and each gate can say yes or no:

| Condition | `True` means | `False` usually means |
| --- | --- | --- |
| `Accepted` | the gate took this route | `allowedRoutes` refuses this namespace, or no listener host name fits the route's `hostnames` |
| `ResolvedRefs` | every `backendRefs` Service was found | a Service name or port is wrong |

`Accepted` is about the gate side, and `ResolvedRefs` is about the backend side. The one that reads `False` tells you which half of the route to fix.

### Read the route's status

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

Two `True` lights: the gate took the route, and the bridge Service exists. `kubectl describe httproute bridge -n starfleet` shows the same conditions in a longer form.

### Break the backend

A typo in a Service name is the most common route mistake. Save the broken version in its own file, so you can switch back easily. Save this as `httproute-bridge-typo.yaml`:

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

Then read the status, send a signal, and read the gate's flight log:

```sh
kubectl get httproute bridge -n starfleet \
  -o jsonpath='{range .status.parents[*].conditions[*]}{.type}={.status} {.reason}: {.message}{"\n"}{end}'
kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" \
  -H "Host: starfleet.example.com" http://starfleet-gateway-istio.starfleet/productpage
kubectl logs -n starfleet deploy/starfleet-gateway-istio --tail=1
```

You should see (log line trimmed):

```text
Accepted=True Accepted: Route was valid
ResolvedRefs=False BackendNotFound: backend(brigde.starfleet.svc.cluster.local) not found
500
[2026-10-08T22:28:51.706Z] "GET /productpage HTTP/1.1" 500 NC cluster_not_found ...
```

The gate still accepts the route, so `Accepted` stays `True`. But `ResolvedRefs` is `False` with the reason `BackendNotFound`, and the message names the missing Service. The gate's proxy answers `500` with the flag `NC`, short for "no cluster": it has nowhere to send the signal. `istioctl analyze -n starfleet` reports the same problem as `IST0171`, a warning that a condition is `False`.

Put the right route back:

```sh
kubectl apply -f httproute-bridge.yaml
```

### Name a gate that does not exist

A typo in `parentRefs` fails more quietly. Change only the gate's name in the route, with a short `kubectl patch`:

```sh
kubectl patch httproute bridge -n starfleet --type json \
  -p '[{"op":"replace","path":"/spec/parentRefs/0/name","value":"starfleet-gate"}]'
```

Then read the route's status, ask the gate how many routes it holds, and send a signal:

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

The route has no status at all: the list of gates is empty. No gate called `starfleet-gate` exists, so no gate answers, and there is nobody to report `Accepted` or `False`. The real gate holds `0` routes and answers `404 NR`. An empty `status.parents` always means "check the name and namespace in `parentRefs`".

Put the right route back:

```sh
kubectl apply -f httproute-bridge.yaml
```

## Weights and filters

`backendRefs` is a list, and each entry takes a `weight`, so traffic shifting is a normal field. This piece of an `HTTPRoute` shows a 90/10 split between two Services (you do not apply it):

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

Each weight goes to a Service, so every version needs its own Service. Your playground has one `scout` Service for all three versions, which is why this is only an example here.

Header changes, redirects and path rewrites go in `filters`. For example, a `RequestHeaderModifier` filter adds a header to every signal that matches the rule:

```yaml
    filters:
    - type: RequestHeaderModifier
      requestHeaderModifier:
        add:
        - name: x-canary
          value: "true"
```

## What stays an Istio object

The Gateway API covers how signals are matched and where they go. Some things it does not cover, and for those you still write Istio objects:

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

A `DestinationRule` belongs to the destination, not to the route. The docking instructions apply to a beacon, whichever flight plan brought the signal there. So a `DestinationRule` for `bridge` still applies when an `HTTPRoute` sends the signal. You do not have to choose between them.

## Common pitfalls

> [!WARNING]
> - **A typo in `backendRefs`.** The route stays `Accepted=True`, but `ResolvedRefs=False BackendNotFound`, and signals get `500 NC`.
> - **A typo in `parentRefs`.** No gate answers, so the route has no status at all. An empty `status.parents` points at `parentRefs`.
> - **Ignoring the status.** The condition that reads `False` names the problem. Read it before you reread the YAML.
> - **Reading `PathPrefix` as a text prefix.** It matches whole path parts, unlike Istio's `uri.prefix`.
> - **Looking for subsets in `backendRefs`.** A backend is a Service. Subsets and traffic policy stay in a `DestinationRule`.

> *`Accepted` is about the gate, and `ResolvedRefs` is about the backend: the light that reads `False` tells you which half to fix.*

## Your mission: Fix The Broken Flight Plans Lab

You can now attach an `HTTPRoute` and read its status lights to find what is wrong. Now prove it in a graded mission: two flight plans are broken in two different ways, and you have to make both work without touching the gate.

The mission runs in its own training solar system, so first pause your playground. Nothing in it is lost:

```sh
astrona stop ats-014-playground-060-03
```

Then start the mission:

```sh
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-060/module-03/labs/lab-03
```

Read the task in [`question.md`](./labs/lab-03/question.md) and solve it on your own first. When you think you are done, send it for grading:

```sh
astrona submit -c sections/section-060/module-03/labs/lab-03
```

When the mission is done, remove it and wake your playground up again:

```sh
astrona destroy ats-014-lab-060-03-03
astrona start ats-014-playground-060-03
```
