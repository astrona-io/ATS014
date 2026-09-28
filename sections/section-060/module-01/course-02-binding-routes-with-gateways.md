# Binding Routes With `gateways:`

> Prerequisite: [The Gateway Pod And Its Listener](./course-01-the-gateway-pod-and-its-listener.md). Next: [Diagnosing The Gateway](./course-03-diagnosing-the-gateway.md).

Part 1 left a listener with nothing attached. This part is the field that attaches routes to it — one line of YAML that is the single most common omission in the whole section.

## The field

The object is the `VirtualService` from section 010, with one addition:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: booking
  namespace: ingress-demo
spec:
  hosts:
    - booking.ica.local
  gateways:
    - booking-gateway          # ← the whole difference
  http:
    - match:
        - uri:
            prefix: /book
      route:
        - destination:
            host: booking-service
            port:
              number: 80
```

Everything except `gateways:` you already know. The `http` rules, the matching, the ordering, the first-match-wins evaluation — all identical to mesh routing.

## `mesh` is a reserved name, and it is the default

Every `VirtualService` you wrote before this section had an implicit `gateways` value:

```yaml
gateways:
  - mesh          # implicit when the field is absent
```

`mesh` is a reserved gateway name meaning **all sidecars**. So the rule is:

> Omit `gateways:` and the routes apply to sidecars only. Name a gateway and they apply to that gateway only.

Omitting the field while expecting north-south routing is the classic failure of this module. The symptom is a persistent 404 from a configuration that looks entirely correct, with no error from the API server and a clean `istioctl analyze`.

The field is a list, so both is possible:

```yaml
gateways:
  - booking-gateway
  - mesh
```

That attaches the same routes to the gateway **and** to in-mesh callers — useful when internal and external traffic should behave identically, and a real decision rather than a default, because they often should not.

> [!TIP]
> **Try it — attach the routes and watch 404 become 200**
>
> ```sh
> kubectl apply -f - <<'EOF'
> apiVersion: networking.istio.io/v1
> kind: VirtualService
> metadata:
>   name: booking
>   namespace: ingress-demo
> spec:
>   hosts:
>     - booking.ica.local
>   gateways:
>     - booking-gateway
>   http:
>     - match:
>         - uri:
>             prefix: /book
>       route:
>         - destination:
>             host: booking-service
>             port:
>               number: 80
> EOF
> sleep 2
> curl -s -o /dev/null -w '%{http_code}\n' -H "Host: booking.ica.local" http://$GATEWAY_URL/book
> ```
>
> Expect something like:
>
> ```text
> 200
> ```
>
> The `Host` header is doing real work: `booking.ica.local` resolves nowhere, so you are connecting to the port-forward and telling the gateway which listener you mean. That is exactly how a real client's DNS name would reach it.

Now remove the one line and watch it break, which is more instructive than reading about it.

> [!TIP]
> **Try it — the same object without `gateways:`**
>
> ```sh
> kubectl -n ingress-demo patch virtualservice booking --type json \
>   -p '[{"op":"remove","path":"/spec/gateways"}]'
> sleep 2
> curl -s -o /dev/null -w '%{http_code}\n' -H "Host: booking.ica.local" http://$GATEWAY_URL/book
> istioctl analyze -n ingress-demo
> ```
>
> Expect something like:
>
> ```text
> 404
> ✔ No validation issues found when analyzing namespace: ingress-demo.
> ```
>
> A 404 and a clean analysis. The routes are perfectly valid — they are just attached to `mesh` instead of to the gateway. Put the field back before continuing; this is the shape of failure to recognise on sight.

## Host overlap between the two objects

The `hosts` of the `VirtualService` must **intersect** the `hosts` of the `Gateway`. They do not have to be identical:

| `Gateway.hosts` | `VirtualService.hosts` | Result |
| --- | --- | --- |
| `booking.ica.local` | `booking.ica.local` | works |
| `*` | `booking.ica.local` | works — the gateway accepts anything, the routes narrow it |
| `*.ica.local` | `booking.ica.local` | works |
| `booking.ica.local` | `shop.ica.local` | **no intersection** — routes attach to nothing |
| `booking.ica.local` | `*` | works, and the listener still only accepts `booking.ica.local` |

A wildcard on one side does not rescue a typo on the other. If the sets do not intersect, the routes attach to nothing and you get a 404 — again with no error.

## Referencing a `Gateway` in another namespace

A common production layout is one shared `Gateway` in `istio-system`, with each team's `VirtualService` in its own namespace attaching to it. The reference then needs the namespace:

```yaml
gateways:
  - istio-system/shared-gateway
```

A bare name is resolved **in the `VirtualService`'s own namespace**. Omit the prefix and Istio looks for a `Gateway` that does not exist there, finds nothing, and attaches the routes to nothing — silent 404.

This is the same short-name-resolution trap as `hosts` in section 010, in a different field, and it is worth recognising as a family: **any short name in an Istio object resolves relative to that object's namespace.**

> [!TIP]
> **Try it — move the `Gateway` and break the reference**
>
> ```sh
> kubectl -n ingress-demo patch virtualservice booking --type merge \
>   -p '{"spec":{"gateways":["istio-system/booking-gateway"]}}'
> sleep 2
> curl -s -o /dev/null -w 'wrong namespace: %{http_code}\n' -H "Host: booking.ica.local" http://$GATEWAY_URL/book
> kubectl -n ingress-demo patch virtualservice booking --type merge \
>   -p '{"spec":{"gateways":["booking-gateway"]}}'
> sleep 2
> curl -s -o /dev/null -w 'correct:         %{http_code}\n' -H "Host: booking.ica.local" http://$GATEWAY_URL/book
> ```
>
> Expect something like:
>
> ```text
> wrong namespace: 404
> correct:         200
> ```
>
> The `Gateway` is in `ingress-demo`, so `istio-system/booking-gateway` names an object that does not exist. Nothing reports the mistake — the routes simply attach to nothing. Getting a feel for this failure now saves a long debugging session later.

> *Omitting `gateways:` means `mesh` — the routes apply to sidecars and the gateway keeps returning 404.*

## Reference

- [VirtualService API](https://istio.io/latest/docs/reference/config/networking/virtual-service/) — the `gateways` field and the reserved `mesh` value.
- [Ingress gateways task](https://istio.io/latest/docs/tasks/traffic-management/ingress/ingress-control/) — the canonical two-object example.
- [Traffic management concepts: gateways](https://istio.io/latest/docs/concepts/traffic-management/#gateways) — why the binding is explicit rather than implicit.
- `istioctl analyze -n <namespace>` — catches a `Gateway` whose selector matches nothing, though not an unbound `VirtualService`.
