# Know What The Ingress API Cannot Express

A Kubernetes `Ingress` is an object that describes how requests from outside the cluster reach a Service inside it. With Istio's ingress gateway, the Envoy proxy at the edge of the mesh, it can route by host and path and add TLS (Transport Layer Security). That is close to all it can do. The exam often asks you to pick the right API (Application Programming Interface) for a task, so knowing where the `Ingress` API stops matters more than any single field. This part lists those limits, shows one of them on a live cluster, and compares the three APIs that can configure the same gateway.

## The features an `Ingress` does not have

An `Ingress` rule has a host, paths, a `pathType` and one backend Service per path. Every Istio feature that needs more than that has no place in the object:

| Istio feature | `Ingress` equivalent |
| --- | --- |
| Weighted routing and canary releases | **none**: there is no `weight` field |
| Mirroring traffic | **none** |
| Matching on headers, query parameters or methods | **none**: host and path only |
| Timeouts and retries | **none** |
| Fault injection | **none** |
| Subsets, load balancing, connection pools, outlier detection | **none**: those live in a `DestinationRule` |
| Choosing which gateway serves it | **none**: always the mesh-wide default gateway |
| Explicit rule order | **none**: the most specific path wins, and the controller decides the details |
| Routing rules that reach across namespaces | **none** |

Other ingress controllers fill these gaps with their own annotations, and each controller has a different set. That works, but it makes an `Ingress` file useless with any other controller. Ending that split is the reason the Kubernetes Gateway API exists. Istio does not add a large set of `Ingress` annotations: if you need more than host and path, you use a different API.

You can check one of these limits yourself. A weighted split needs a list of backends with a weight on each. Ask `kubectl` what a path's backend can hold.

<!-- astrona:playground:renew -->

```sh
kubectl explain ingress.spec.rules.http.paths.backend
```

You should see this (shortened to the fields):

```text
FIELDS:
  resource	<TypedLocalObjectReference>
  service	<IngressServiceBackend>
```

A backend is one Service or one other object. There is no `weight` field and no list, so an `Ingress` cannot split requests between two backends, for example 90% to `probe` v1 and 10% to `probe` v2.

## Choosing between the three APIs

Three APIs can configure the same ingress gateway to send requests to the same Service. Istio's own `Gateway` object opens ports on the gateway, and a `VirtualService` bound to it sets the routes. The Kubernetes `Ingress` does both jobs in one small object. The Gateway API is a newer set of Kubernetes objects (`GatewayClass`, `Gateway`, `HTTPRoute`) that works the same way with any implementation. Pick by what the task needs:

| Situation | Use |
| --- | --- |
| Existing `Ingress` files you want served without a rewrite | **`Ingress`** with `ingressClassName: istio` |
| You need weights, header matching, retries, mirroring, faults or subsets | Istio's **`Gateway` with a `VirtualService`** |
| New work, and you want files that work with any implementation | The **Gateway API** |
| A platform team owns the gateway, and application teams own their routes | The **Gateway API**: its objects split that ownership |

Istio supports `Ingress` so that a move to Istio does not have to start with a rewrite of every routing file. It is a compatibility feature, not the best way to configure Istio.

You now know that an `Ingress` handles host, path and TLS, and nothing else: no weights, no header matching, no retries, no timeouts, no faults. When a task needs any of those, the answer is a `VirtualService` or the Gateway API. The graded mission below puts the whole `Ingress` workflow together: the class, the two path types and TLS.

## Common pitfalls

> [!WARNING]
> - **Expecting Istio features from an `Ingress`.** No weights, no header matching, no retries, no timeouts, no faults. Those need a `VirtualService` or the Gateway API.
> - **Adding another controller's annotations.** Annotations written for nginx or a cloud controller do nothing in Istio.
> - **Looking for a field that picks the gateway.** Every `Ingress` goes through the mesh-wide default gateway, `istio-ingressgateway` with pods labelled `istio: ingressgateway`.
> - **Choosing `Ingress` for new work that needs traffic shifting.** You would have to rewrite it later. Start with a `VirtualService` or the Gateway API.

## Your mission: Expose A Service With A Kubernetes Ingress

You can now assign an `Ingress` to Istio, route hosts and paths with the right `pathType`, and add TLS with the secret in the gateway's namespace. The mission asks you to build all three for a small application called `booking-service`, which is a different application from the one in the playground.

The mission runs in its own cluster, so first pause your playground. Nothing in it is lost:

```sh
astrona stop ats-014-playground-060-02
```

Then start the mission:

```sh
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-060/module-02/labs/lab-01
```

The task is on the next page. Solve it on your own first. When you think you are done, send it for grading:

```sh
astrona submit -c sections/section-060/module-02/labs/lab-01
```

When you have finished, remove the mission and start your playground again:

```sh
astrona destroy ats-014-lab-060-02
astrona start ats-014-playground-060-02
```
