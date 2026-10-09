# Decide Who May Dock

Astronaut, a spaceport often serves more than one crew. The platform crew owns the gate, and application crews on other planets want to dock their flight plans there. The Gateway API does not let them in by accident: the gate's owner decides, in the `Gateway` itself, which planets may attach routes.

The commands below need the `starfleet-gateway` `Gateway` (with `allowedRoutes` set to `from: Same`) and the `bridge` `HTTPRoute` in the `starfleet` namespace. If `kubectl get gateway,httproute -n starfleet` misses one, apply your `gateway-starfleet.yaml` and `httproute-bridge.yaml` again.

## `allowedRoutes` is closed by default

Each listener has an `allowedRoutes` field. Think of it as the spaceport's landing list: only ships from the planets on the list may dock. It has three settings:

| `allowedRoutes.namespaces.from` | Routes may attach from |
| --- | --- |
| `Same` | only the `Gateway`'s own namespace. This is **the default** |
| `All` | any namespace |
| `Selector` | namespaces whose labels match a selector you write |

A route that is not allowed does not attach. It says why in its own status, with `Accepted=False`. `allowedRoutes` also has a `kinds` field, which limits the route kinds a listener takes, for example only `HTTPRoute`.

A route in another namespace must also name the gate's namespace in `parentRefs`. Without it, the route points at a gate on its own planet, finds none, and gets no status at all.

<!-- astrona:playground:renew -->

### Dock a route from another planet

The `probe` lives on the `outpost` planet. Its crew wants signals for `/hostname` sent to it, through your gate. Save this as `httproute-probe.yaml`:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: probe
  namespace: outpost
spec:
  parentRefs:
  - name: starfleet-gateway
    namespace: starfleet
  hostnames:
  - starfleet.example.com
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /hostname
    backendRefs:
    - name: probe
      port: 8000
```

The `namespace: starfleet` line under `parentRefs` points at the gate on the other planet. The backend `probe` is a short name, so it means the `probe` Service on the route's own planet, `outpost`.

Apply it:

```sh
kubectl apply -f httproute-probe.yaml
```

Then read the route's status and send a signal:

```sh
kubectl get httproute probe -n outpost \
  -o jsonpath='{range .status.parents[*].conditions[*]}{.type}={.status} {.reason}: {.message}{"\n"}{end}'
kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" \
  -H "Host: starfleet.example.com" http://starfleet-gateway-istio.starfleet/hostname
```

You should see:

```text
Accepted=False NotAllowedByListeners: hostnames matched parent hostname "starfleet.example.com", but namespace "outpost" is not allowed by the parent
ResolvedRefs=True ResolvedRefs: All references resolved
404
```

The gate found the route, and the host name fits, but the listener only allows `Same`. So the gate refused it with `NotAllowedByListeners`, and the signal gets `404`. The backend is fine (`ResolvedRefs=True`): this is purely a question of permission.

### Open the gate by label

Allowing `All` would let any planet in, including ones you never meant to. The `Selector` form is a deliberate grant: only planets that carry a label you choose. Save this as `gateway-starfleet-selector.yaml`:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: starfleet-gateway
  namespace: starfleet
  annotations:
    networking.istio.io/service-type: ClusterIP
spec:
  gatewayClassName: istio
  listeners:
  - name: http
    port: 80
    protocol: HTTP
    hostname: starfleet.example.com
    allowedRoutes:
      namespaces:
        from: Selector
        selector:
          matchLabels:
            gateway-access: "true"
```

It is the same `Gateway`, with only `allowedRoutes` changed. Apply it:

```sh
kubectl apply -f gateway-starfleet-selector.yaml
```

Then read the status of both routes:

```sh
kubectl get httproute probe -n outpost \
  -o jsonpath='{range .status.parents[*].conditions[*]}{.type}={.status} {.reason}{"\n"}{end}'
kubectl get httproute bridge -n starfleet \
  -o jsonpath='{range .status.parents[*].conditions[*]}{.type}={.status} {.reason}{"\n"}{end}'
```

You should see:

```text
Accepted=False NotAllowedByListeners
ResolvedRefs=True ResolvedRefs
Accepted=False NotAllowedByListeners
ResolvedRefs=True ResolvedRefs
```

Now **both** routes are refused, even `bridge`, which lives on the gate's own planet. A `Selector` gives nothing for free: no planet has the label yet, and that includes `starfleet`.

### Label the planets

Give both planets the label the selector asks for:

```sh
kubectl label namespace outpost gateway-access=true
kubectl label namespace starfleet gateway-access=true
```

Then read both routes' status again, and send one signal to each backend through the same gate:

```sh
kubectl get httproute probe -n outpost \
  -o jsonpath='{range .status.parents[*].conditions[*]}{.type}={.status} {.reason}{"\n"}{end}'
kubectl get httproute bridge -n starfleet \
  -o jsonpath='{range .status.parents[*].conditions[*]}{.type}={.status} {.reason}{"\n"}{end}'
kubectl exec -n starfleet deploy/shuttle -- curl -s \
  -H "Host: starfleet.example.com" http://starfleet-gateway-istio.starfleet/hostname
kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" \
  -H "Host: starfleet.example.com" http://starfleet-gateway-istio.starfleet/productpage
```

You should see (the pod name changes between runs):

```text
Accepted=True Accepted
ResolvedRefs=True ResolvedRefs
Accepted=True Accepted
ResolvedRefs=True ResolvedRefs
{
  "hostname": "probe-v1-7888d6c6d5-qtfrv"
}
200
```

Both routes dock now. The `/hostname` signal crossed from the `starfleet` planet, through the gate, to a probe on `outpost`, and the probe answered with its pod name. The bridge answers `200` again. Remove a label, and that planet's route is refused within seconds. The gate's owner controls access with a namespace label, without editing any route.

## Common pitfalls

> [!WARNING]
> - **A route in another namespace with `from: Same`.** It stays `Accepted=False NotAllowedByListeners`.
> - **Forgetting the gate's own namespace with `Selector`.** The selector does not include it for free. Label it too, or its routes are refused.
> - **Leaving `namespace` out of a cross-namespace `parentRefs`.** The route looks for the gate on its own planet, and gets no status at all.
> - **Reaching for `All`.** It works, but it lets every namespace attach. A `Selector` is a deliberate grant.
> - **Host names that do not fit the listener.** The gate refuses the route with `Accepted=False NoMatchingListenerHostname`, whatever `allowedRoutes` says.

> *`allowedRoutes` is the gate's landing list: closed by default, opened on purpose, one planet label at a time.*

## Your mission: Share One Gateway Between Two Planets Lab

You can now let routes from chosen namespaces dock at a gate, and read why a route was refused. Now prove it in a graded mission: build one shared gate from scratch, with a label-based landing list, and dock routes from two different planets.

The mission runs in its own training solar system, so first pause your playground. Nothing in it is lost:

```sh
astrona stop ats-014-playground-060-03
```

Then start the mission:

```sh
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-060/module-03/labs/lab-01
```

Read the task in [`question.md`](./labs/lab-01/question.md) and solve it on your own first. When you think you are done, send it for grading:

```sh
astrona submit -c sections/section-060/module-03/labs/lab-01
```

When the mission is done, remove it and wake your playground up again:

```sh
astrona destroy ats-014-lab-060-03
astrona start ats-014-playground-060-03
```
