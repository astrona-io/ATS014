# TLS And The Feature Ceiling

> Prerequisite: [Rules, Path Types And Translation](./course-02-rules-path-types-and-translation.md). Next: [the module landing page](./course.md).

Two things left: the TLS configuration, whose one non-obvious rule causes most of the failures on this topic, and an honest account of what the `Ingress` API cannot do — which is the whole reason the next module exists.

## TLS on an `Ingress`

The configuration itself is two fields:

```yaml
spec:
  ingressClassName: istio
  tls:
    - hosts:
        - booking.ica.local
      secretName: booking-credential
  rules:
    - host: booking.ica.local
      ...
```

`secretName` names an ordinary Kubernetes TLS secret (`kubernetes.io/tls`, holding `tls.crt` and `tls.key`).

## The namespace rule

> **The secret must exist in the gateway's namespace** — normally `istio-system` — **not in the application's namespace.**

This differs from how nearly every other Kubernetes object behaves, and it follows directly from *where the reading happens*. The gateway pod loads the certificate, and a pod can only read secrets from its own namespace. The `Ingress` object lives with your application; the process that needs the key lives somewhere else.

The failure is quiet and asymmetric:

- HTTP keeps working perfectly.
- HTTPS refuses the connection — `curl` reports `000`, or a connection reset.
- The `Ingress` status says nothing. No event, no warning.

That combination — HTTP fine, HTTPS dead, no error — is the signature. Check which namespace the secret is in before anything else.

> [!TIP]
> **Try it — the wrong namespace, then the right one**
>
> ```sh
> openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
>   -keyout /tmp/booking.key -out /tmp/booking.crt \
>   -subj "/CN=booking.ica.local/O=ica" 2>/dev/null
>
> # first, deliberately in the APPLICATION namespace
> kubectl -n k8s-ingress-demo create secret tls booking-credential \
>   --key=/tmp/booking.key --cert=/tmp/booking.crt
> kubectl -n k8s-ingress-demo patch ingress booking --type merge -p '
> spec:
>   tls:
>     - hosts:
>         - booking.ica.local
>       secretName: booking-credential'
> kubectl -n istio-system port-forward svc/istio-ingressgateway 8443:443 >/dev/null 2>&1 &
> sleep 3
> curl -sk -o /dev/null -w 'secret in app namespace:     %{http_code}\n' \
>   --resolve booking.ica.local:8443:127.0.0.1 https://booking.ica.local:8443/book
> curl -s -o /dev/null -w 'plain HTTP still fine:       %{http_code}\n' \
>   -H "Host: booking.ica.local" http://$GATEWAY_URL/book
> ```
>
> Expect something like:
>
> ```text
> secret in app namespace:     000
> plain HTTP still fine:       200
> ```
>
> `000` means curl never completed a connection — the HTTPS listener was never brought up, because the gateway could not read the secret. And HTTP is untouched, which is exactly why this mistake survives a casual test.

Now move it and watch it recover.

> [!TIP]
> **Try it — the secret where the gateway can read it**
>
> ```sh
> kubectl -n istio-system create secret tls booking-credential \
>   --key=/tmp/booking.key --cert=/tmp/booking.crt
> sleep 5
> curl -sk -o /dev/null -w 'secret in gateway namespace: %{http_code}\n' \
>   --resolve booking.ica.local:8443:127.0.0.1 https://booking.ica.local:8443/book
> ```
>
> Expect something like:
>
> ```text
> secret/booking-credential created
> secret in gateway namespace: 200
> ```
>
> Nothing about the `Ingress` changed — only where the secret lives. `-k` skips verification because the certificate is self-signed, and `--resolve` makes curl send the right SNI and `Host` for a name that resolves nowhere.

## What the API cannot express

This is the part worth remembering for the exam, more than any field name. The `Ingress` API has host and path routing, and that is essentially all:

| Istio feature | `Ingress` equivalent |
| --- | --- |
| Weighted routing / canary (section 020) | **none** — no `weight` field exists |
| Mirroring (section 020) | **none** |
| Header, query or method matching (section 010) | **none** — host and path only |
| Timeouts and retries (section 040) | **none** |
| Fault injection (section 050) | **none** |
| Subsets, load balancer policy, connection pools, outlier detection | **none** — all `DestinationRule` concerns |
| Choosing which gateway serves it | **none** — the mesh-wide default gateway |
| Explicit rule ordering | **none** — most-specific-match, implementation-defined |
| Cross-namespace routing rules | **none** |

Controllers have historically papered over this with vendor-specific annotations — `nginx.ingress.kubernetes.io/...`, and a different set for every implementation. That worked, and it made `Ingress` manifests completely non-portable, which is precisely the fragmentation the Kubernetes Gateway API was created to end.

Istio deliberately does **not** add a large annotation vocabulary. If you need more than host and path, the answer is a different API rather than an annotation.

## Choosing between the three

| Situation | Use |
| --- | --- |
| Existing `Ingress` manifests you want served without a rewrite | **`Ingress`** with `ingressClassName: istio` |
| You need weights, header matching, retries, mirroring, faults, subsets | **`Gateway` + `VirtualService`** (module 1) |
| New work, and you want portability across implementations | **Gateway API** (module 3) |
| Platform team owns the listener, app teams own the routes | **Gateway API** — the role split is built into the objects |

The honest summary: `Ingress` support exists so a migration does not have to be a rewrite. It is a bridge, and this module's purpose is to let you cross it knowingly.

## Common pitfalls

> [!WARNING]
> **Creating the TLS secret in the application namespace.** The gateway reads secrets from its own namespace (`istio-system`). HTTP keeps working, HTTPS silently never comes up.
>
> **Omitting `ingressClassName`.** Another controller may claim the object, or none will. An unclaimed `Ingress` is a 404 with no error — check the `CLASS` column.
>
> **Getting `spec.controller` wrong on the `IngressClass`.** It must be exactly `istio.io/ingress-controller`.
>
> **Reading `pathType: Prefix` as a string prefix.** It is element-wise: `/book` does not match `/booking`. Istio's own `uri.prefix` behaves differently.
>
> **Expecting Istio features from an `Ingress`.** No weights, no header matching, no retries, no timeouts, no faults. Those need `Gateway` + `VirtualService`.
>
> **Relying on rule ordering.** The `Ingress` spec says most-specific-match and leaves details to the controller. You cannot see or control the order.
>
> **Mixing `ingressClassName` and the legacy annotation inconsistently.** Pick one.
>
> **Expecting the `ADDRESS` column to confirm health.** On a cluster with no load balancer it stays empty regardless.

> *The `Ingress` TLS secret lives in the gateway's namespace, because the gateway pod is what has to read it.*

## Reference

- [Istio Kubernetes Ingress task](https://istio.io/latest/docs/tasks/traffic-management/ingress/kubernetes-ingress/) — including the secret-namespace requirement.
- [Kubernetes Ingress TLS](https://kubernetes.io/docs/concepts/services-networking/ingress/#tls) — the `spec.tls` structure and secret format.
- [Gateway API rationale](https://gateway-api.sigs.k8s.io/) — the Kubernetes project's own account of what `Ingress` could not do.
- [Secure gateways task](https://istio.io/latest/docs/tasks/traffic-management/ingress/secure-ingress/) — the native `Gateway` equivalent, where the same namespace rule applies.
