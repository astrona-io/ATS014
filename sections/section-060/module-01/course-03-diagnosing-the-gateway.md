# Diagnosing The Gateway

> Prerequisite: [Binding Routes With `gateways:`](./course-02-binding-routes-with-gateways.md). Next: [the module landing page](./course.md).

Gateway problems present as two status codes, and almost all of the diagnostic value is in telling them apart. This part is that distinction, the commands that settle it, and the module's consolidated pitfalls.

## 404 versus 503

| Code | Means | Look at |
| --- | --- | --- |
| **404** | the request did not match a listener **and** a route | `Host` header, `Gateway.hosts`, `VirtualService.hosts`, whether `gateways:` is set, namespace of the `Gateway` reference |
| **503** | it matched, but the upstream could not be reached | `destination.host`, the port number, whether a named subset exists, whether the backend pods are ready |

Worth memorising as a sentence: **404 is my configuration, 503 is my backend.**

The distinction is sharp because these are different stages. A 404 means Envoy never found a route entry to use. A 503 means it found one, selected a cluster, and that cluster had nothing healthy to send to. Section 010's endpoint-list check applies unchanged.

> [!TIP]
> **Try it — produce each failure deliberately**
>
> ```sh
> echo "--- wrong Host (no listener match) ---"
> curl -s -o /dev/null -w '%{http_code}\n' -H "Host: wrong.ica.local" http://$GATEWAY_URL/book
> echo "--- right Host, unmatched path (no route match) ---"
> curl -s -o /dev/null -w '%{http_code}\n' -H "Host: booking.ica.local" http://$GATEWAY_URL/nothing-here
> echo "--- route matches, destination does not exist ---"
> kubectl -n ingress-demo patch virtualservice booking --type merge \
>   -p '{"spec":{"http":[{"match":[{"uri":{"prefix":"/book"}}],"route":[{"destination":{"host":"no-such-service","port":{"number":80}}}]}]}}'
> sleep 2
> curl -s -o /dev/null -w '%{http_code}\n' -H "Host: booking.ica.local" http://$GATEWAY_URL/book
> ```
>
> Expect something like:
>
> ```text
> --- wrong Host (no listener match) ---
> 404
> --- right Host, unmatched path (no route match) ---
> 404
> --- route matches, destination does not exist ---
> 503
> ```
>
> Two 404s from different causes, then a 503 from a third. The first two are indistinguishable by status code alone — which is why the next section's route dump matters. Restore the correct destination (`booking-service`) before moving on.

## Reading the gateway's own configuration

The gateway is an ordinary Envoy, so `istioctl proxy-config` works on it exactly as on a sidecar. Two commands settle almost everything:

**`listener`** answers "is anything accepting traffic on this port?" — which covers a `Gateway` whose selector matched nothing, or a port you did not open.

**`routes`** answers "did my `VirtualService` attach?" — which covers the `gateways:` omission, a host mismatch, and a cross-namespace reference.

> [!TIP]
> **Try it — the routes the gateway proxy actually holds**
>
> ```sh
> istioctl proxy-config routes deploy/istio-ingressgateway -n istio-system | grep -i booking
> istioctl analyze -n ingress-demo
> ```
>
> Expect something like:
>
> ```text
> http.8080     booking.ica.local     /book*     booking.ingress-demo
> ✔ No validation issues found when analyzing namespace: ingress-demo.
> ```
>
> The host appears with its path match and the `VirtualService` that produced it. **If your host is absent from this list, the `VirtualService` never attached** — and that is the single most useful check in the module, because it distinguishes "my routes are wrong" from "my routes are not there".

Note that `istioctl analyze` is clean in both the working and the unbound case. It cross-references objects that reference each other; a `VirtualService` attached to `mesh` instead of a gateway is a perfectly valid object, so there is nothing for it to report.

## A short diagnostic order

When a gateway task does not work, this sequence resolves it faster than re-reading YAML:

1. **`curl` with the right `Host`** — 404 or 503? That halves the search space immediately.
2. **`istioctl proxy-config routes deploy/istio-ingressgateway -n istio-system`** — is your host there at all?
   - Absent → `gateways:` field, host overlap, or the namespace of the `Gateway` reference.
   - Present → the routes attached; the problem is downstream.
3. **`istioctl proxy-config endpoints deploy/istio-ingressgateway -n istio-system`** — does the destination cluster have endpoints? (For a 503.)
4. **`istioctl analyze -n <namespace>`** — catches subset references and selectors matching nothing.

## Common pitfalls

> [!WARNING]
> **Omitting `gateways:` in the `VirtualService`.** The routes attach to `mesh` and the gateway keeps returning 404 no matter how correct they look. The single most common mistake in this section.
>
> **Host mismatch between `Gateway` and `VirtualService`.** The two host sets must intersect. A `*` on one side does not rescue a typo on the other.
>
> **Referencing a cross-namespace `Gateway` without `<namespace>/<name>`.** Silent 404 — the short name resolves in the `VirtualService`'s own namespace.
>
> **Reading a 503 as a routing problem.** 503 means routing worked. Check the destination host, port, subset and endpoints.
>
> **Forgetting the `Host` header when testing.** Without it, curl sends the address you dialled, which matches no listener. Every test in this module needs `-H "Host: ..."`.
>
> **Expecting `EXTERNAL-IP` on a cluster with no load balancer.** `<pending>` is normal on `kind`; use a port-forward or a NodePort.
>
> **A `Gateway` selector matching no pod.** The object exists and configures nothing. `istioctl analyze` reports this one.
>
> **Declaring `protocol: TCP` for HTTP traffic.** You get a byte pipe with no host or path routing, which looks like routing that silently ignores your rules.
>
> **Trusting a clean `istioctl analyze`.** It does not know your `VirtualService` was supposed to be attached to a gateway.

> *404 is my configuration and 503 is my backend — and the gateway's own route dump says which of the two 404s you have.*

## Reference

- [Ingress gateways task](https://istio.io/latest/docs/tasks/traffic-management/ingress/ingress-control/) — including the troubleshooting section.
- [Debugging Envoy and istiod](https://istio.io/latest/docs/ops/diagnostic-tools/proxy-cmd/) — `proxy-config` against a gateway rather than a sidecar.
- [Istio analyzer messages](https://istio.io/latest/docs/reference/config/analysis/) — what `analyze` does and does not catch.
- `istioctl proxy-config routes deploy/istio-ingressgateway -n istio-system` — the one command that separates "wrong routes" from "no routes".
