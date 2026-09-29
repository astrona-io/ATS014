# Rules, Path Types And Translation

> Prerequisite: [Claiming An Ingress](./course-01-claiming-an-ingress.md). Next: [TLS And The Feature Ceiling](./course-03-tls-and-the-feature-ceiling.md).

The rule structure is Kubernetes', not Istio's, and one of its fields behaves differently from the Istio field with the same name. This part covers the shape, that difference, and what Istio builds out of it.

## The rule structure

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: booking
  namespace: k8s-ingress-demo
spec:
  ingressClassName: istio
  rules:
    - host: booking.ica.local
      http:
        paths:
          - path: /book
            pathType: Prefix
            backend:
              service:
                name: booking-service
                port:
                  number: 80
```

The nesting is deeper than Istio's for the same information: `rules[].http.paths[].backend.service.name`. Two structural points:

- **`host` is optional.** A rule with no `host` matches any hostname — the `Ingress` equivalent of `hosts: ["*"]`.
- **`backend.service` names a Kubernetes Service directly.** There is no host string and no subset concept, which is the first hint of the feature ceiling in Part 3.

## `pathType`, and the trap

`pathType` is required on every path, and it has three values:

| Value | Matches |
| --- | --- |
| `Exact` | the path exactly, and nothing below it |
| `Prefix` | the path split on `/`, **element by element** |
| `ImplementationSpecific` | left to the controller — avoid when you want portable behaviour |

The one to be careful with is `Prefix`, because it is **element-wise, not a string prefix**:

Side by side against Istio's own `uri.prefix` from section 010, which **is** a plain string prefix, for the same configured value `/book`:

| Request path | `Ingress` `pathType: Prefix` | Istio `uri: { prefix: /book }` |
| --- | --- | --- |
| `/book` | matches | matches |
| `/book/` | matches | matches |
| `/book/123` | matches — element `book`, then more | matches |
| `/booking` | **no match** — the element is `booking` | **matches** |
| `/bookings/1` | **no match** | **matches** |

The last two rows are the whole difference: `Ingress` compares path *elements*, Istio compares *characters*.

Same word, different semantics, in two APIs you will translate between. When converting an `Ingress` to a `VirtualService`, a `pathType: Prefix` of `/book` becomes `uri: { prefix: /book/ }` plus an `exact` match on `/book` if you want to be faithful — or you accept that the Istio version is slightly broader.

> [!TIP]
> **Try it — `Prefix` is element-wise**
>
> ```sh
> for p in /book /book/123 /booking /bookings; do
>   printf '%-12s -> ' "$p"
>   curl -s -o /dev/null -w '%{http_code}\n' -H "Host: booking.ica.local" "http://$GATEWAY_URL$p"
> done
> ```
>
> Expect something like:
>
> ```text
> /book        -> 200
> /book/123    -> 200
> /booking     -> 404
> /bookings    -> 404
> ```
>
> `/booking` is a 404 even though it starts with the characters `/book`. Write the equivalent rule as an Istio `VirtualService` with `uri: { prefix: /book }` and that same request would be a 200 — which is why this is worth knowing before you migrate anything.

## Watching the translation

Istio does not run a separate `Ingress` implementation. `istiod` **translates** the object into the same internal gateway configuration a `Gateway` plus `VirtualService` would produce, and pushes that to the gateway proxy.

Two consequences, both useful:

- Everything you learned in module 1 about diagnosing a gateway applies unchanged. The route table is the ground truth, and your `Ingress` either appears in it or does not.
- The translation is one-way and internal. There is no `Gateway` object to `kubectl get`, and no way to hand-edit the intermediate form.

> [!TIP]
> **Try it — the translated route in the gateway proxy**
>
> ```sh
> kubectl -n k8s-ingress-demo get ingress booking
> istioctl proxy-config routes deploy/istio-ingressgateway -n istio-system | grep -i booking
> kubectl -n k8s-ingress-demo get gateway,virtualservice
> ```
>
> Expect something like:
>
> ```text
> NAME      CLASS   HOSTS               ADDRESS   PORTS   AGE
> booking   istio   booking.ica.local             80      4m
> http.8080   booking.ica.local   /book*   booking-service.k8s-ingress-demo
> No resources found in k8s-ingress-demo namespace.
> ```
>
> The route is in the gateway's table, and there is **no `Gateway` and no `VirtualService`** in the namespace. Compare that middle line with module 1's output for the equivalent native objects — they are nearly identical, because they are the same internal configuration arrived at by two routes.

## Multiple rules and multiple paths

One `Ingress` can carry several hosts, each with several paths:

```yaml
spec:
  ingressClassName: istio
  rules:
    - host: booking.ica.local
      http:
        paths:
          - path: /book
            pathType: Prefix
            backend: { service: { name: booking-service, port: { number: 80 } } }
          - path: /health
            pathType: Exact
            backend: { service: { name: booking-service, port: { number: 80 } } }
    - host: catalog.ica.local
      http:
        paths:
          - path: /items
            pathType: Prefix
            backend: { service: { name: catalog-service, port: { number: 80 } } }
```

Note what is **not** here: any way to express ordering. Istio's `VirtualService` evaluates `http` rules top down and first match wins, and you control that order. The `Ingress` API has no such guarantee — the specification says the most specific match wins, and leaves the details to the controller.

For non-overlapping paths that is fine. For overlapping ones it means the behaviour is defined by the implementation rather than by your YAML, which is a real reason to prefer an API where you can see the ordering.

> *`pathType: Prefix` is element-wise and Istio's `uri.prefix` is a string prefix — the same word means two different things in the two APIs.*

## Common pitfalls

> [!WARNING]
> **Reading `Prefix` as a string prefix.** It is element-wise. `/book` does not match `/booking`, which is the opposite of Istio's `uri.prefix`.
>
> **Translating a `pathType: Prefix` to `uri.prefix` verbatim.** The Istio version is broader. Use `prefix: /book/` plus an `exact` match on `/book` to be faithful.
>
> **Assuming `ImplementationSpecific` behaves consistently.** Its meaning is up to the controller, so a manifest that worked on another ingress controller may not behave the same here.
>
> **Expecting rule order to decide precedence.** `Ingress` has no first-match-wins list; longest path wins, which is a different model from the `VirtualService` you translate it into.

## Reference

- [Ingress path types](https://kubernetes.io/docs/concepts/services-networking/ingress/#path-types) — the three values with the specification's own examples.
- [Ingress path matching precedence](https://kubernetes.io/docs/concepts/services-networking/ingress/#multiple-matches) — what the spec says about overlapping paths.
- [Istio Kubernetes Ingress task](https://istio.io/latest/docs/tasks/traffic-management/ingress/kubernetes-ingress/) — the translation in practice.
- [HTTPMatchRequest](https://istio.io/latest/docs/reference/config/networking/virtual-service/#HTTPMatchRequest) — Istio's `uri.prefix`, for the comparison above.
