# Expose A Service With A Kubernetes Ingress

<!-- astrona:playground -->
> [!NOTE]
> 🧪 **Hands-on playground for this module** — a clean, throwaway machine to explore on. No task, no grading. Folder: [`playground/`](https://github.com/astrona-io/ATS014/tree/main/sections/section-060/module-02/playground)
>
> ```sh
> astrona run --git ssh://git@github.com/astrona-io/ATS014.git -c sections/section-060/module-02/playground
> astrona destroy ats-014-playground-060-02
> ```

Kubernetes had an ingress API before Istio existed, and a great deal of existing YAML uses it. Istio's gateway can serve that API too: point an `Ingress` at Istio's ingress class and the same gateway pod you configured in module 1 handles it, with no `Gateway` and no `VirtualService` anywhere.

This is a **migration and compatibility feature**, not the recommended way to configure Istio. Knowing *why* — what the `Ingress` API structurally cannot express — is more examinable than the YAML itself, and it is the reason the next module exists.

## How this module is organised

1. **[Part 1 — Claiming An Ingress](./course-01-claiming-an-ingress.md)** — how a controller takes ownership of an `Ingress`, the two ways to select Istio, and what an unclaimed object looks like.
2. **[Part 2 — Rules, Path Types And Translation](./course-02-rules-path-types-and-translation.md)** — the rule structure, the three `pathType` values and the element-wise trap, and watching Istio translate the object into gateway configuration.
3. **[Part 3 — TLS And The Feature Ceiling](./course-03-tls-and-the-feature-ceiling.md)** — the secret-namespace rule that catches everyone, an honest inventory of what `Ingress` cannot do, and how to choose between the three APIs in this section.

## Learning objectives

After this module you can:

- Make Istio's gateway serve a Kubernetes `Ingress`, in both the current and legacy selection form.
- Explain what an `IngressClass` is and what happens to an `Ingress` no controller claims.
- Write an `Ingress` rule routing a host and path to a Service, choosing the right `pathType`.
- Explain how `pathType: Prefix` differs from Istio's `uri.prefix`.
- Configure TLS on an `Ingress` and place the secret in the namespace the gateway can actually read.
- List the Istio features that have no expression in the `Ingress` API, and choose between `Ingress`, `Gateway` + `VirtualService`, and the Gateway API.

## Before you start

You need module 1 of this section: the ingress gateway pod, the port-forward pattern, and the 404-versus-503 distinction all carry over unchanged.

The playground gives you a single-node `kind` cluster with **Istio 1.30.5 already installed** (the `demo` profile, including the ingress gateway) and the namespace **`k8s-ingress-demo`**, injected, containing `booking-service` on port 80. No `Ingress` and no `IngressClass` exist yet.

Set up the port-forward again and leave it running:

```sh
kubectl -n istio-system port-forward svc/istio-ingressgateway 8080:80 >/dev/null 2>&1 &
export GATEWAY_URL=localhost:8080
```

## Where this fits

Three APIs, one gateway pod, one backend. Module 1 was Istio's native pair. This module is the API that came first and can express the least. Module 3 is the portable successor the Kubernetes project built to replace it. The ICA expects you to recognise which API a task is written in and to know what each one cannot do — that recognition is most of the value of reading all three.
