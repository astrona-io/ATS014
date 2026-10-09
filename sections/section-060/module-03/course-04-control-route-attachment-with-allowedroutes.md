# Control Route Attachment With allowedRoutes

One gateway often serves more than one team. The cluster operator owns the `Gateway`, and application developers in other namespaces want to attach their `HTTPRoute` objects to it. The Gateway API does not let them attach by accident: the owner of the `Gateway` decides, in the `Gateway` itself, which namespaces may attach routes. This part shows that check failing, and then opens it on purpose for chosen namespaces.

The commands below need the `starfleet-gateway` `Gateway` (with `allowedRoutes` set to `from: Same`) and the `bridge` `HTTPRoute` in the `starfleet` namespace. If `kubectl get gateway,httproute -n starfleet` misses one, apply your `gateway-starfleet.yaml` and `httproute-bridge.yaml` again.

## `allowedRoutes` is closed by default

Each listener of a `Gateway` has an `allowedRoutes` field. Its `namespaces.from` setting decides which namespaces may attach routes to that listener:

| `allowedRoutes.namespaces.from` | Routes may attach from |
| --- | --- |
| `Same` | only the `Gateway`'s own namespace. This is **the default** |
| `All` | any namespace |
| `Selector` | namespaces whose labels match a label selector you write |

A route that is not allowed does not attach, and Istio's controller says why in the route's own status, with `Accepted=False`. `allowedRoutes` also has a `kinds` field, which limits the route kinds a listener accepts, for example only `HTTPRoute`.

A route in another namespace must also name the `Gateway`'s namespace in `parentRefs`. Without it, the route looks for the `Gateway` in its own namespace, finds none, and gets no status at all.

## A route from another namespace

The `probe` Service runs in the `outpost` namespace. It is an HTTP echo server: it answers with details about the request it received. The route below sends requests for `/hostname` through `starfleet-gateway` to the `probe` Service.

<!-- astrona:playground:renew -->

Save this as `httproute-probe.yaml`:

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

The `namespace: starfleet` line under `parentRefs` points at the `Gateway` in the other namespace. The backend `probe` has no namespace, so it means the `probe` Service in the route's own namespace, `outpost`.

Apply it:

```sh
kubectl apply -f httproute-probe.yaml
```

Then check the result. Read the route's status, and send a request from the `shuttle` pod:

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

The controller found the route, and the host name matches the listener. But the listener only allows `Same`, so the controller refused the route with `NotAllowedByListeners`, and the request gets `404`. The backend is fine (`ResolvedRefs=True`): the only problem is permission.

## Allow namespaces by label

`from: All` would let any namespace attach, including namespaces you never meant to allow. The `Selector` form is a deliberate grant: only namespaces that carry a label you choose may attach. The `Gateway` below is the same as before, with only `allowedRoutes` changed.

Save this as `gateway-starfleet-selector.yaml`:

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

Apply it:

```sh
kubectl apply -f gateway-starfleet-selector.yaml
```

Then check the result. Read the status of both routes:

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

Now **both** routes are refused, even `bridge`, which lives in the `Gateway`'s own namespace. A `Selector` allows only what it matches. No namespace has the label yet, and that includes `starfleet`.

## Label the namespaces

To finish the grant, give both namespaces the label that the selector asks for:

```sh
kubectl label namespace outpost gateway-access=true
kubectl label namespace starfleet gateway-access=true
```

Then read the status of both routes again, and send one request to each backend through the same gateway:

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

You should see this (the pod name differs on your cluster):

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

Both routes are attached now. The request for `/hostname` went from the `shuttle` pod in `starfleet`, through the gateway proxy, to a `probe` pod in `outpost`, and the `probe` answered with its pod name. The `bridge` Service answers `200` again. If you remove the label from a namespace, the controller refuses that namespace's route within seconds. The owner of the `Gateway` controls access with a namespace label, without editing any route.

You can now let routes from chosen namespaces attach to a `Gateway`, and read from a route's status why it was refused. You have also seen that a `Selector` does not include the `Gateway`'s own namespace for free. Together with creating a `Gateway` and writing `HTTPRoute` objects, that covers the everyday work of ingress with the Gateway API.

## Common pitfalls

> [!WARNING]
> - **A route in another namespace with `from: Same`.** It stays `Accepted=False NotAllowedByListeners`.
> - **Forgetting the `Gateway`'s own namespace with `Selector`.** The selector does not include it for free. Label it too, or its routes are refused.
> - **Leaving `namespace` out of a cross-namespace `parentRefs`.** The route looks for the `Gateway` in its own namespace, and gets no status at all.
> - **Choosing `All` by default.** It works, but it lets every namespace attach. A `Selector` is a deliberate grant.
> - **Host names that do not match the listener.** The controller refuses the route with `Accepted=False NoMatchingListenerHostname`, whatever `allowedRoutes` says.

## Your mission: Share One Gateway API Gateway Across Two Namespaces Lab

You can now control which namespaces may attach routes to a `Gateway` with a label selector. The mission asks you to build one shared `Gateway` from scratch, allow namespaces by label, and attach routes from two different namespaces to it.

The lab runs on its own cluster, so first pause your playground. Nothing in it is lost:

```sh
astrona stop ats-014-playground-060-03
```

Then start the lab. The task is on the next page; solve it on your own first:

```sh
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-060/module-03/labs/lab-01
```

When you think you are done, send it for grading:

```sh
astrona submit -c sections/section-060/module-03/labs/lab-01
```

When the lab is done, remove it and start your playground again:

```sh
astrona destroy ats-014-lab-060-03
astrona start ats-014-playground-060-03
```
