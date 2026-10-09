# Hosts And References At The Gate

Astronaut, a `Gateway` and a `VirtualService` each carry a list of hosts, and the flight plan names the gate it belongs to. This part covers how those names have to line up: which hosts overlap, what `*` really does, and how to name a gate on another planet. You also see that the flight plan behind the gate can use subsets, just like inside the mesh.

The commands below need the `starfleet-gateway` `Gateway` and the `bridge` `VirtualService` applied (host `starfleet.example.com`, `gateways: [starfleet-gateway]`), and the `gateway_status` helper pasted.

## The two host lists must overlap

Both objects have `hosts`, and the gate only uses a flight plan where the two lists overlap. They do not have to be the same. One wrong host shows the rule better than the table does, so start with that.

<!-- astrona:playground:renew -->

### Give the flight plan a host the gate does not serve

This flight plan asks for `shop.example.com`, a host the `Gateway` does not list. Save this as `virtualservice-bridge-wrong-host.yaml`:

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

Then check the result with both host names, and ask `istioctl analyze`:

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

(The `analyze` output is trimmed to its finding.)

Both signals get `404`. `starfleet.example.com` has no flight plan any more, and `shop.example.com` is not a host on the gate, so the gate drops the plan for every host. Here `istioctl analyze` helps: warning `IST0132` names the host that the `Gateway` does not serve.

### The overlap rules

The general rule: the gate uses a flight plan only for hosts that **both** lists accept.

| `Gateway.hosts` | `VirtualService.hosts` | Result |
| --- | --- | --- |
| `starfleet.example.com` | `starfleet.example.com` | works |
| `*.example.com` | `starfleet.example.com` | works |
| `*` | `starfleet.example.com` | works for `Host: starfleet.example.com` only |
| `starfleet.example.com` | `*` | works, and the gate still only accepts `starfleet.example.com` |
| `starfleet.example.com` | `shop.example.com` | **no overlap**: the gate ignores the flight plan |

A `*` on one side never fixes a typo on the other. On the playground, a `Gateway` with `hosts: ["*"]` and the `bridge` flight plan for `starfleet.example.com` still answers `404` to a signal with no `Host` header. Only with `"*"` on **both** objects does `curl http://localhost:8080/productpage` with no `Host` header get `200`.

That is handy for a quick test, or an exam task that names no host. In real systems, use real host names: with `"*"`, every flight plan linked to that gate competes for the same hosts.

## The flight plan behind the gate is a normal flight plan

A route at the gate can use everything a route inside the mesh can: subsets, weights, retries, faults. The gate reads the docking instructions (the `DestinationRule`) the same way a sidecar does. The playground already has the `scout` `DestinationRule` with the subsets `v1`, `v2` and `v3`.

### Send outside signals for the scout to its v3 class

This flight plan adds a first rule: signals for `/reviews/<id>` from outside go straight to the `v3` scout. It also fixes the host back to `starfleet.example.com`. Save this as `virtualservice-bridge-with-scout-api.yaml`:

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

Then check the result: send five signals to the scout through the gate and count which ship class answered, then check the bridge still works:

```sh
for i in 1 2 3 4 5; do curl -s -H "Host: starfleet.example.com" http://localhost:8080/reviews/0 | grep -o 'scout-v[0-9]'; done | sort | uniq -c
gateway_status /productpage
```

```text
   5 scout-v3
200
```

All five signals reached `scout-v3`. Without the first rule, the scout's beacon would spread them over all three classes. The second rule still sends `/productpage` to the bridge.

## Naming a gate on another planet

A common real layout is one shared `Gateway` on a central planet, with each team's flight plan on its own planet linking to it. The link then needs the planet's name:

```yaml
gateways:
- istio-ingress/shared-gateway
```

A bare name is looked up **on the flight plan's own planet** (its namespace). The same goes for every short name in an Istio object: it is filled in from that object's own namespace. So a `<namespace>/<name>` link only works if the `Gateway` really lives in that namespace.

### Point the link at the wrong planet

The `Gateway` object lives in `starfleet`, not on the gateway pods' planet `istio-ingress`. This flight plan links to it as if it lived in `istio-ingress`. Save this as `virtualservice-bridge-wrong-namespace.yaml`:

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

(The `analyze` output is trimmed to its findings.)

The gate answers `404`, because the flight plan links to a gate that does not exist. `istioctl analyze` catches it: `IST0101 Referenced gateway not found`, plus `IST0132` for the same missing gate. To fix it, link to the planet where the `Gateway` really is. Here that is the plan's own planet, so the bare name `starfleet-gateway` works, and so would `starfleet/starfleet-gateway`.

### Restore the working flight plan

Apply the bridge flight plan you saved earlier again:

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

The gate routes to the bridge again. This file has no scout rule, so `/reviews/0` is back to `404` at the gate.

> [!TIP]
> Before you write `<namespace>/<name>` in `gateways:`, look the `Gateway` up: `kubectl get gateway -A`. The planet in the first column is the one to write, and it is often not the gateway pods' planet.

## Common pitfalls

> [!WARNING]
> - **A flight plan host that the `Gateway` does not serve.** Only the overlap of the two host lists counts. `istioctl analyze` warns with `IST0132`.
> - **Expecting `*` on the `Gateway` to accept signals with any host.** The flight plan still needs a matching host. Use `*` on both objects, or real host names.
> - **Linking to the gateway pods' planet instead of the `Gateway` object's planet.** The pods live in `istio-ingress`; the object can live anywhere. `istioctl analyze` reports `IST0101 Referenced gateway not found`.
> - **Linking to a `Gateway` on another planet with a bare name.** A short name is looked up on the flight plan's own planet. Use `<namespace>/<name>`.

> *The gate uses a flight plan only where both host lists overlap, and only if `gateways:` names the right gate on the right planet.*

## Your mission: Expose A Service With An Istio Ingress Gateway

You can now link flight plans to the gate and line up their hosts. Now prove it in a graded mission: open one gate for two hosts, and steer each host to its own ship, so that each host carries only its own routes.

This mission's solar system installs Istio with the `istioctl` `demo` profile, not with Helm. So its gateway pods live on the planet `istio-system` and carry the label `istio: ingressgateway`, and the ships have their own names. The task tells you everything you need.

The mission runs in its own training solar system, so first pause your playground. Nothing in it is lost:

```sh
astrona stop ats-014-playground-060-01
```

Then start the mission:

```sh
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-060/module-01/labs/lab-01
```

Read the task in [`question.md`](./labs/lab-01/question.md) and solve it on your own first. When you think you are done, send it for grading:

```sh
astrona submit -c sections/section-060/module-01/labs/lab-01
```

When the mission is done, remove it and wake your playground up again:

```sh
astrona destroy ats-014-lab-060-01
astrona start ats-014-playground-060-01
```
