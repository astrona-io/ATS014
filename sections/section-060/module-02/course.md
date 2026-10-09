# Expose A Service With A Kubernetes Ingress

Astronaut, Kubernetes had its own way to let signals from outside into the solar system long before Istio existed: the `Ingress` API. A great deal of existing YAML is written in it. Istio's ingress gateway can serve that API too. Point an `Ingress` at Istio's ingress class, and the gateway pod handles it, with no `Gateway` and no `VirtualService` anywhere.

Think of it as an older docking standard that the new spaceport still accepts. It is a **migration and compatibility feature**, not the best way to configure Istio. Knowing *why*, that is, what the `Ingress` API cannot express, matters more in the exam than the YAML itself.

## Learning objectives

After this module you can:

- Make Istio's ingress gateway serve a Kubernetes `Ingress`, with the `ingressClassName` field or the older annotation.
- Explain what an `IngressClass` is, and recognise an `Ingress` that no controller serves.
- Write an `Ingress` rule that routes a host and a path to a Service, choosing the right `pathType`.
- Explain how `pathType: Prefix` differs from Istio's own `uri.prefix`.
- Configure TLS on an `Ingress`, with the secret in the namespace the gateway can read.
- List the Istio features the `Ingress` API cannot express, and choose between `Ingress`, `Gateway` with `VirtualService`, and the Gateway API.

## Before you start

Every mission starts with a pre-flight check, astronaut. Before you write your first `Ingress`, make sure you have the knowledge this module expects, and know what is waiting in your playground.

### What you should already know

- **How the mesh works.** A proxy (the communications officer) sits beside every pod, and `istiod` (mission control) sends it orders. You can read those orders with `istioctl proxy-config`.
- **What an ingress gateway is.** A standalone proxy at the edge of the mesh: the spaceport arrival gate that signals from outside the solar system come through. Here it is the Deployment `istio-ingressgateway` in the namespace `istio-system`.
- **Kubernetes basics.** Namespaces, Deployments, Services and `kubectl apply`.

### What is in your playground

Your playground is a small training solar system: one `kind` cluster with **Istio 1.30.5** and its ingress gateway already installed. The ships live on one planet, the namespace **`starfleet`**:

| Ship | Its role in the fleet |
| --- | --- |
| `bridge` | The **flagship**. Its page, `/productpage` on port `9080`, is what you open to the outside |
| `probe` v1, v2 | The **echo probe** on port `8000`. It answers any path under `/anything`, so it shows exactly which paths the gate lets through |
| `cargo`, `scout` v1/v2/v3, `navcom` | The rest of the fleet. The bridge signals them to build its page |
| `shuttle` | **Your shuttle** inside the mesh |

There is **no** `IngressClass` and **no** `Ingress` yet. Writing them is your mission in this module.

The gate is already reachable from your own machine. Your playground forwards two local ports to the ingress gateway:

| On your machine | Gateway port |
| --- | --- |
| `http://localhost:8080` | `80` (plain HTTP) |
| `https://localhost:8443` | `443` (HTTPS, once a TLS `Ingress` exists) |

Launch your playground now, and keep it running next to you while you read the parts:

<!-- astrona:playground -->

### One variable to set first

Paste this into each new terminal. Every command in this module sends its signals through it:

```sh
GATEWAY_URL=localhost:8080
```

## Why this matters

Three APIs can open the same arrival gate to the same flagship: Istio's own `Gateway` with a `VirtualService`, the Kubernetes `Ingress` in this module, and the newer Gateway API. The exam expects you to recognise which API a task is written in, and to know what each one cannot do. The `Ingress` is the oldest and can express the least, so it is the one you most often have to translate from.
