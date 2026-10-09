# Match Hosts And Reference Gateways Across Namespaces

A `Gateway` and a `VirtualService` each carry a list of hosts, and the `VirtualService` names the `Gateway` it belongs to. If these names do not line up, the gateway answers `404` and the objects still look correct. This part shows how the names must match: which hosts overlap, what `*` really does, and how to name a `Gateway` in another namespace.

You also see that the routes on the gateway can use subsets, just like routes inside the mesh. The commands below need the `starfleet-gateway` `Gateway` (selector `istio: ingress`, port `80`, host `starfleet.example.com`) and the `bridge` `VirtualService` applied. That `VirtualService` serves `starfleet.example.com`, has `gateways: [starfleet-gateway]`, and is saved as `virtualservice-bridge.yaml`. The commands also use the `gateway_status` helper, which sends one request through the gateway with a `Host` header and prints the status code:

<!-- astrona:playground:renew -->

```sh
gateway_status() { curl -s -o /dev/null -w "%{http_code}\n" -H "Host: ${2:-starfleet.example.com}" "http://localhost:8080$1"; }
```

## The two host lists must overlap

Both objects have a `hosts` field, and the gateway uses a `VirtualService` only for the hosts where the two lists overlap. The lists do not have to be the same. One wrong host shows the rule faster than a table does, so start with that.

### Give the VirtualService a host the Gateway does not serve

This `VirtualService` asks for `shop.example.com`, a host the `Gateway` does not list. Save this as `virtualservice-bridge-wrong-host.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: bridge
  namespace: starfleet
spec:
  hosts:
  - shop.example.com
  gateways:
  - starfleet-gateway
  http:
  - route:
    - destination:
        host: bridge
        port:
          number: 9080
```

Apply it:

```sh
kubectl apply -f virtualservice-bridge-wrong-host.yaml
```

```text
virtualservice.networking.istio.io/bridge configured
```

Then check the result with both host names, and run `istioctl analyze`:

```sh
gateway_status /productpage
gateway_status /productpage shop.example.com
istioctl analyze -n starfleet
```

```text
404
404
Warning [IST0132] (VirtualService starfleet/bridge) one or more host [shop.example.com] defined in VirtualService starfleet/bridge not found in Gateway starfleet/starfleet-gateway.
```

(The `analyze` output is shortened to its finding.)

Both requests get `404`. `starfleet.example.com` has no `VirtualService` any more, and `shop.example.com` is not a host on the `Gateway`. So `istiod` gives the gateway no routes from this `VirtualService` for any host. Here `istioctl analyze` helps: warning `IST0132` names the host that the `Gateway` does not serve.

### The overlap rules

The general rule is that the gateway uses a `VirtualService` only for hosts that both lists accept:

| `Gateway.hosts` | `VirtualService.hosts` | Result |
| --- | --- | --- |
| `starfleet.example.com` | `starfleet.example.com` | works |
| `*.example.com` | `starfleet.example.com` | works |
| `*` | `starfleet.example.com` | works for `Host: starfleet.example.com` only |
| `starfleet.example.com` | `*` | works, and the gateway still only accepts `starfleet.example.com` |
| `starfleet.example.com` | `shop.example.com` | **no overlap**: the gateway ignores the `VirtualService` |

A `*` on one side never fixes a typo on the other. On the playground, a `Gateway` with `hosts: ["*"]` and the `bridge` `VirtualService` for `starfleet.example.com` still answers `404` to a request with no `Host` header. Only with `"*"` on both objects does `curl http://localhost:8080/productpage` with no `Host` header get `200`.

That is handy for a quick test, or for an exam task that names no host. In real systems, use real host names. With `"*"`, every `VirtualService` bound to that `Gateway` competes for the same hosts.

## Routes on the gateway work like routes in the mesh

With the hosts lined up, the routes themselves hold no surprises. A route on the gateway can use everything a route inside the mesh can: subsets, weights, retries and faults. The gateway's Envoy reads the `DestinationRule` (the object that defines subsets and traffic policy for a host) the same way a sidecar proxy does. The playground already has the `scout` `DestinationRule` with the subsets `v1`, `v2` and `v3`. A subset is a named group of a Service's pods, selected by labels.

### Send outside requests for scout to subset v3

This `VirtualService` adds a first rule: requests for `/reviews/<id>` from outside go straight to `scout` subset `v3`. It also sets the host back to `starfleet.example.com`. Save this as `virtualservice-bridge-with-scout-api.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: bridge
  namespace: starfleet
spec:
  hosts:
  - starfleet.example.com
  gateways:
  - starfleet-gateway
  http:
  - match:
    - uri:
        prefix: /reviews/
    route:
    - destination:
        host: scout
        subset: v3
        port:
          number: 9080
  - match:
    - uri:
        exact: /productpage
    - uri:
        prefix: /static
    - uri:
        exact: /login
    - uri:
        exact: /logout
    - uri:
        prefix: /api/v1/products
    route:
    - destination:
        host: bridge
        port:
          number: 9080
```

Apply it:

```sh
kubectl apply -f virtualservice-bridge-with-scout-api.yaml
```

```text
virtualservice.networking.istio.io/bridge configured
```

Then check the result. Send five requests to `scout` through the gateway and count which version answered, then check that `bridge` still works:

```sh
for i in 1 2 3 4 5; do curl -s -H "Host: starfleet.example.com" http://localhost:8080/reviews/0 | grep -o 'scout-v[0-9]'; done | sort | uniq -c
gateway_status /productpage
```

```text
   5 scout-v3
200
```

All five requests reached `scout-v3`. Without `subset: v3`, the gateway's Envoy would spread them over the pods of all three `scout` versions. The second rule still sends `/productpage` to `bridge`.

## Naming a Gateway in another namespace

The last name that must line up is the `Gateway` reference itself. A common real layout is one shared `Gateway` in a central namespace, with each team's `VirtualService` in its own namespace. The reference in `gateways:` then needs the namespace:

```yaml
gateways:
- istio-ingress/shared-gateway
```

A bare name is looked up in the `VirtualService`'s own namespace. The same goes for every short name in an Istio object: Istio fills in the namespace of the object that holds the name. So a `<namespace>/<name>` reference only works if the `Gateway` really lives in that namespace.

### Point the reference at the wrong namespace

The `Gateway` object lives in `starfleet`, not in `istio-ingress`, the namespace of the gateway pods. This `VirtualService` refers to it as if it lived in `istio-ingress`. Save this as `virtualservice-bridge-wrong-namespace.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: bridge
  namespace: starfleet
spec:
  hosts:
  - starfleet.example.com
  gateways:
  - istio-ingress/starfleet-gateway
  http:
  - match:
    - uri:
        exact: /productpage
    - uri:
        prefix: /static
    - uri:
        exact: /login
    - uri:
        exact: /logout
    - uri:
        prefix: /api/v1/products
    route:
    - destination:
        host: bridge
        port:
          number: 9080
```

Apply it:

```sh
kubectl apply -f virtualservice-bridge-wrong-namespace.yaml
```

```text
virtualservice.networking.istio.io/bridge configured
```

Then check the result:

```sh
gateway_status /productpage
istioctl analyze -n starfleet
```

```text
404
Error [IST0101] (VirtualService starfleet/bridge) Referenced gateway not found: "istio-ingress/starfleet-gateway"
Warning [IST0132] (VirtualService starfleet/bridge) one or more host [starfleet.example.com] defined in VirtualService starfleet/bridge not found in Gateway istio-ingress/starfleet-gateway.
```

(The `analyze` output is shortened to its findings.)

The gateway answers `404`, because the `VirtualService` refers to a `Gateway` that does not exist. `istioctl analyze` catches it: `IST0101 Referenced gateway not found`, plus `IST0132` for the same missing `Gateway`. To fix it, use the namespace where the `Gateway` really is. Here that is the `VirtualService`'s own namespace, so the bare name `starfleet-gateway` works, and so does `starfleet/starfleet-gateway`.

### Restore the working VirtualService

Apply the `bridge` `VirtualService` from `virtualservice-bridge.yaml` again:

```sh
kubectl apply -f virtualservice-bridge.yaml
```

```text
virtualservice.networking.istio.io/bridge configured
```

Then check the result:

```sh
gateway_status /productpage
```

```text
200
```

The gateway routes to `bridge` again. This file has no `scout` rule, so `/reviews/0` gets `404` at the gateway again.

> [!TIP]
> Before you write `<namespace>/<name>` in `gateways:`, look the `Gateway` up with `kubectl get gateway -A`. Write the namespace from the first column. It is often not the namespace of the gateway pods.

You now know the three names that must line up: the hosts on both objects, and the `Gateway` reference with its namespace. Each mistake gives the same `404`, and `istioctl analyze` names most of them. The open question is how to tell all the gateway failures apart when you do not know which object is wrong.

## Common pitfalls

> [!WARNING]
> - **A `VirtualService` host that the `Gateway` does not serve.** Only the overlap of the two host lists counts. `istioctl analyze` warns with `IST0132`.
> - **Expecting `*` on the `Gateway` to accept requests with any host.** The `VirtualService` still needs a matching host. Use `*` on both objects, or real host names.
> - **Using the gateway pods' namespace instead of the `Gateway` object's namespace.** The pods live in `istio-ingress`; the object can live in any namespace. `istioctl analyze` reports `IST0101 Referenced gateway not found`.
> - **Referring to a `Gateway` in another namespace with a bare name.** A short name is looked up in the `VirtualService`'s own namespace. Use `<namespace>/<name>`.

## Your mission: Expose Two Hosts Through One Ingress Gateway Lab

You can now bind a `VirtualService` to a `Gateway` and line up their hosts. In the lab, you open one `Gateway` for two hosts and route each host to its own Service, so that each host carries only its own routes.

The lab uses a different application from the Starfleet, and it installs Istio with the `istioctl` `demo` profile instead of Helm. So its gateway pods live in the `istio-system` namespace and carry the label `istio: ingressgateway`. The task gives you every name you need.

The lab runs in its own cluster, so first pause your playground. Nothing in it is lost:

```sh
astrona stop ats-014-playground-060-01
```

Then start the lab:

```sh
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-060/module-01/labs/lab-01
```

The task is on the next page. Solve it on your own first. When you think you are done, send it for grading:

```sh
astrona submit -c sections/section-060/module-01/labs/lab-01
```

When the lab is done, remove it and start your playground again:

```sh
astrona destroy ats-014-lab-060-01
astrona start ats-014-playground-060-01
```
