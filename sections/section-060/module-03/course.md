# Ingress With The Kubernetes Gateway API

Requests from outside the cluster enter the mesh through an ingress gateway: an Envoy proxy at the edge of the mesh that accepts traffic from outside the cluster and forwards it to a Service inside. Kubernetes and Istio offer more than one API to configure that gateway. This module teaches the newest one, the **Kubernetes Gateway API**.

The Gateway API is a standard set of objects, written by the Kubernetes project, that many tools implement. Istio is one of them. You describe the gateway with these objects, and Istio deploys and configures the proxy for you. Each object also reports its own status conditions, so you can see what went wrong without guessing.

## Learning objectives

After this module you can:

- Name the three Gateway API objects, `GatewayClass`, `Gateway` and `HTTPRoute`, and say which role owns each one.
- Explain why `no matches for kind "Gateway"` means the Gateway API is missing from the cluster, not that Istio is broken.
- Create a Gateway API `Gateway` and find the proxy that Istio deploys for it in the `Gateway`'s own namespace.
- Write an `HTTPRoute` with `parentRefs`, `hostnames`, `matches` and `backendRefs`, and send a request through it.
- Read the `Accepted`, `Programmed` and `ResolvedRefs` conditions, and tell from them which object to fix.
- Control which namespaces may attach routes to a `Gateway` with `allowedRoutes`.
- Say which Istio objects you still need when the routing is done with the Gateway API.

## Before you start

This module expects some knowledge of the mesh and of Kubernetes, and it uses a ready-made playground. Check both before you begin.

### What you should already know

- **How the mesh works.** Istio adds a sidecar proxy (Envoy) to each pod: a proxy container that all inbound and outbound traffic of the pod passes through. `istiod`, Istio's control plane, sends configuration to every proxy.
- **Kubernetes basics.** Namespaces, Deployments, Services, labels and `kubectl exec`.
- **A `VirtualService` helps.** It is Istio's own routing object. Much of the `HTTPRoute` object maps onto it field by field, so it is easier if you have written one before.

### What is in your playground

Your playground is one `kind` cluster with **Istio 1.30.5** installed with Helm. It also has the **Gateway API CRDs installed**, because they are not part of Kubernetes or Istio. There is no Istio ingress gateway: in this module you create your own.

Two namespaces are ready:

| Namespace | What runs in it |
| --- | --- |
| `starfleet` | The sample app: `bridge` (the web frontend), `cargo`, `navcom`, `scout` v1, v2 and v3, and `shuttle`, the test client pod |
| `outpost` | `probe` v1 and v2, an HTTP echo server on port `8000`. It stands for a second team in another namespace that wants to use your gateway |

Every application pod shows `2/2`: the application container plus its `istio-proxy` sidecar. There is **no** `Gateway` and **no** `HTTPRoute` yet.

The URL paths inside the applications are fixed by their images: the `bridge` page is at `/productpage`, and `scout` answers at `/reviews/0`.

Start your playground now, and keep it running while you read the parts:

<!-- astrona:playground -->

## The parts of this module

The module has four parts and three graded labs. Each lab comes right after the part it practises, and a summary closes the module.

1. **The Gateway API Objects And Their Owners.** The three Gateway API objects, why their CRDs must be installed separately, and what Istio registers when they are there.
2. **A Gateway That Creates Its Own Data Plane.** Create a `Gateway`, find the proxy that Istio deploys for it, and read its conditions. The lab after it asks you to create a `Gateway` for a route that is already waiting.
3. **Attach An HTTPRoute And Read Its Status.** Send requests through the gateway, and read the route's conditions when it is wrong. The lab after it asks you to fix two broken routes.
4. **Control Route Attachment With allowedRoutes.** Let a route from another namespace use your gateway, on purpose. The lab after it asks you to build one gateway shared by two namespaces.
