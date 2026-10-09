# Expose A Service With A Kubernetes Ingress

Kubernetes had its own API (Application Programming Interface) for traffic from outside the cluster long before Istio existed: the `Ingress`. An `Ingress` is an object that describes how HTTP requests for a host and a path reach a Service inside the cluster. A lot of existing YAML is written with it, and Istio's ingress gateway can serve it. Point an `Ingress` at Istio's ingress class, and the gateway handles it, with no `Gateway` and no `VirtualService` anywhere.

This is a migration and compatibility feature, not the best way to configure Istio. For the exam, knowing what the `Ingress` API cannot express matters more than the YAML itself.

## Learning objectives

After this module you can:

- Make Istio's ingress gateway serve a Kubernetes `Ingress`, with the `ingressClassName` field or the older annotation.
- Explain what an `IngressClass` is, and recognise an `Ingress` that no controller serves.
- Write an `Ingress` rule that routes a host and a path to a Service, and choose the right `pathType`.
- Explain how `pathType: Prefix` differs from Istio's own `uri.prefix`.
- Configure TLS (Transport Layer Security) on an `Ingress`, with the secret in the namespace the gateway reads.
- List the Istio features the `Ingress` API cannot express, and choose between `Ingress`, `Gateway` with `VirtualService`, and the Gateway API.

## Before you start

This module expects some knowledge, and it uses a playground with the example workloads already running.

### What you should already know

- **How the mesh works.** Istio adds a sidecar proxy (Envoy) to each pod, and all traffic of the pod passes through it. `istiod`, Istio's control plane, sends configuration to every proxy. You can read that configuration with `istioctl proxy-config`.
- **What an ingress gateway is.** An ingress gateway is an Envoy proxy at the edge of the mesh that accepts traffic from outside the cluster. Here it is the Deployment `istio-ingressgateway` in the namespace `istio-system`.
- **Kubernetes basics.** Namespaces, Deployments, Services and `kubectl apply`.

### What is in your playground

Your playground is one `kind` cluster with **Istio 1.30.5** and its ingress gateway already installed. The example workloads run in the namespace **`starfleet`**:

| Workload | What it is |
| --- | --- |
| `bridge` | Web frontend. Its page, `/productpage` on port `9080`, is what you expose to the outside |
| `probe` v1, v2 | HTTP echo server on port `8000`. It answers any path under `/anything`, so it shows exactly which paths the gateway lets through |
| `cargo`, `scout` v1/v2/v3, `navcom` | Backends that `bridge` calls to build its page |
| `shuttle` | Test client pod inside the mesh |

There is **no** `IngressClass` and **no** `Ingress` yet. You write them in this module.

The playground forwards two local ports to the ingress gateway:

| On your machine | Gateway port |
| --- | --- |
| `http://localhost:8080` | `80` (plain HTTP) |
| `https://localhost:8443` | `443` (HTTPS, once a TLS `Ingress` exists) |

Start your playground now, and keep it running while you read the parts:

<!-- astrona:playground -->

### One variable to set first

Paste this into each new terminal. Every command in this module sends its requests through it:

```sh
GATEWAY_URL=localhost:8080
```

## How this module is organised

The module has four parts. The first part creates the `IngressClass` for Istio, assigns an `Ingress` to it, and shows what happens when no controller serves an `Ingress`; a short troubleshooting lab follows it. The second part explains the rule format and `pathType`, and reads the routes that `istiod` builds from an `Ingress`. The third part adds TLS and shows why the secret must be in the gateway's namespace. The fourth part lists what the `Ingress` API cannot express and compares the three ingress APIs; the module's main lab follows it. A summary closes the module.
