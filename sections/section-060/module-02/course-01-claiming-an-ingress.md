# Claiming An Ingress

> Prerequisite: [the module landing page](./course.md). Next: [Rules, Path Types And Translation](./course-02-rules-path-types-and-translation.md).

An `Ingress` object on its own belongs to nobody. Some controller has to take ownership of it, and the mechanism for that ownership — plus the silent failure when nothing does — is this part.

## The ownership problem

A cluster can run several ingress controllers at once: nginx, Istio, a cloud provider's, all watching the same API. Something has to decide which of them implements a given `Ingress`, and that something is the **ingress class**.

There are two ways to express it, and you will meet both:

| Form | Status | Looks like |
| --- | --- | --- |
| `spec.ingressClassName` | current | `ingressClassName: istio` |
| `kubernetes.io/ingress.class` annotation | legacy, deprecated, still honoured | `kubernetes.io/ingress.class: istio` |

The annotation predates the field and survives in a great deal of older YAML. Prefer the field for anything new; recognise the annotation when reading somebody else's manifests. Setting both inconsistently is the one thing to avoid, because which wins depends on version and is not worth relying on.

## `IngressClass` and the controller string

`ingressClassName` refers to a cluster-scoped `IngressClass` object, which names the controller that implements it:

```yaml
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  name: istio
spec:
  controller: istio.io/ingress-controller
```

Two fields, each doing one job:

- **`metadata.name`** is the string an `Ingress` puts in `ingressClassName`. It is arbitrary — `istio` is convention, not a requirement.
- **`spec.controller`** is the fixed identifier `istiod` watches for: **`istio.io/ingress-controller`**. This one is not arbitrary. Get it wrong and the class exists, `Ingress` objects reference it happily, and nothing implements them.

The object is cluster-scoped and created once. Whether it already exists depends on how Istio was installed, so checking is the first step rather than an assumption.

> [!TIP]
> **Try it — is there an `istio` ingress class yet?**
>
> ```sh
> kubectl get ingressclass
> kubectl -n k8s-ingress-demo get ingress
> ```
>
> Expect something like:
>
> ```text
> No resources found
> No resources found in k8s-ingress-demo namespace.
> ```
>
> Nothing on either side. If an `istio` class were already present you would reuse it rather than create a second one — an ingress class is cluster-wide and shared by every namespace.

## What an unclaimed `Ingress` looks like

This is the failure worth seeing deliberately, because it produces no error anywhere.

An `Ingress` with no class, or with a class no controller implements, is simply ignored. The object is valid. `kubectl apply` succeeds. No event is recorded, no status is set, no log line appears. Requests 404 — and from Kubernetes' point of view there is no problem at all, because nothing ever claimed responsibility.

The tell is in `kubectl get ingress`: the **`CLASS`** column, and the **`ADDRESS`** column staying empty.

> [!TIP]
> **Try it — an `Ingress` nobody implements**
>
> ```sh
> kubectl apply -f - <<'EOF'
> apiVersion: networking.k8s.io/v1
> kind: Ingress
> metadata:
>   name: booking
>   namespace: k8s-ingress-demo
> spec:
>   rules:
>     - host: booking.ica.local
>       http:
>         paths:
>           - path: /book
>             pathType: Prefix
>             backend:
>               service:
>                 name: booking-service
>                 port:
>                   number: 80
> EOF
> kubectl -n k8s-ingress-demo get ingress booking
> curl -s -o /dev/null -w '%{http_code}\n' -H "Host: booking.ica.local" http://$GATEWAY_URL/book
> ```
>
> Expect something like:
>
> ```text
> ingress.networking.k8s.io/booking created
> NAME      CLASS    HOSTS               ADDRESS   PORTS   AGE
> booking   <none>   booking.ica.local             80      3s
> 404
> ```
>
> `CLASS: <none>` and an empty `ADDRESS`. The object was accepted and nothing is serving it. That pair of empty columns is the signature to recognise.

## Claiming it

Create the class and point the `Ingress` at it, and the same object starts working with no other change.

> [!TIP]
> **Try it — create the class and claim the object**
>
> ```sh
> kubectl apply -f - <<'EOF'
> apiVersion: networking.k8s.io/v1
> kind: IngressClass
> metadata:
>   name: istio
> spec:
>   controller: istio.io/ingress-controller
> EOF
> kubectl -n k8s-ingress-demo patch ingress booking --type merge \
>   -p '{"spec":{"ingressClassName":"istio"}}'
> sleep 3
> kubectl -n k8s-ingress-demo get ingress booking
> curl -s -o /dev/null -w '%{http_code}\n' -H "Host: booking.ica.local" http://$GATEWAY_URL/book
> ```
>
> Expect something like:
>
> ```text
> ingressclass.networking.k8s.io/istio created
> ingress.networking.k8s.io/booking patched
> NAME      CLASS   HOSTS               ADDRESS   PORTS   AGE
> booking   istio   booking.ica.local             80      1m
> 200
> ```
>
> `CLASS: istio` and a `200`. The rules never changed — only who was listening. Note `ADDRESS` may stay empty on `kind` because there is no load balancer address to publish; that column is not a reliable health signal here.

## Which gateway serves it

One detail that matters for a multi-gateway cluster: Istio serves `Ingress` objects through the gateway identified by the `ingressService` and `ingressSelector` settings in the mesh configuration, which by default point at `istio-ingressgateway`.

So an `Ingress` goes to the default gateway, and there is no per-object way to say otherwise. If you need a particular application on a particular gateway — an internal one, say — the `Ingress` API cannot express it, and that is the first entry in Part 3's list of things it cannot do.

> *An `Ingress` no controller claims is a valid object that nothing serves — check the `CLASS` column before debugging anything else.*

## Common pitfalls

> [!WARNING]
> **Leaving `ingressClassName` off.** Nothing claims the `Ingress`, nothing serves it, and there is no error anywhere — only a resource with no address.
>
> **Using the deprecated `kubernetes.io/ingress.class` annotation.** It still works in places and is not the field to reach for on a current cluster.
>
> **Expecting Istio to serve an `Ingress` claimed by another controller.** Both controllers see the object; only the one named by the class acts on it.
>
> **Looking for a `Gateway` object.** Istio synthesises the gateway configuration from the `Ingress`. There is no `Gateway` in your namespace to inspect.

## Reference

- [Kubernetes Ingress API](https://kubernetes.io/docs/concepts/services-networking/ingress/) — the object, its history, and the class mechanism.
- [IngressClass](https://kubernetes.io/docs/concepts/services-networking/ingress/#ingress-class) — the field, the annotation, and default classes.
- [Istio Kubernetes Ingress task](https://istio.io/latest/docs/tasks/traffic-management/ingress/kubernetes-ingress/) — Istio's own walkthrough, including the controller string.
- [MeshConfig `ingressService` / `ingressSelector`](https://istio.io/latest/docs/reference/config/istio.mesh.v1alpha1/#MeshConfig) — which gateway serves `Ingress` objects.
