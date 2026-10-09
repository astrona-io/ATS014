# Ingress With The Kubernetes Gateway API

Astronaut, signals from outside your solar system need a door to come in through. In space terms that door is the spaceport arrival gate: one place where outside signals land, get checked, and get sent on to the right ship. Kubernetes and Istio give you more than one way to build that gate.

This module teaches the newest one, the **Kubernetes Gateway API**. It is a standard set of objects, written by the Kubernetes project, that many tools understand. Istio is one of them. You describe the gate with these objects, and Istio builds and runs it for you.

The Gateway API splits the work into three objects, each owned by a different crew. One crew picks the spaceport model, one crew builds the spaceport, and one crew writes the flight plans for the signals that land there. Each object also reports its own status, like a row of lights on a launch panel, so you can see what went wrong without guessing.

## Learning objectives

After this module you can:

- Name the three Gateway API objects, `GatewayClass`, `Gateway` and `HTTPRoute`, and say which crew owns each one.
- Explain why `no matches for kind "Gateway"` means the Gateway API is missing from the cluster, not that Istio is broken.
- Create a Gateway API `Gateway` and find the proxy that Istio builds for it in the `Gateway`'s own namespace.
- Write an `HTTPRoute` with `parentRefs`, `hostnames`, `matches` and `backendRefs`, and send a signal through it.
- Read the `Accepted`, `Programmed` and `ResolvedRefs` conditions, and tell from them which object to fix.
- Control which namespaces may attach routes to a `Gateway` with `allowedRoutes`.
- Say which Istio objects you still need when the routing is done with the Gateway API.

## Before you start

Every mission starts with a pre-flight check, astronaut. Make sure you have the knowledge this module expects and know what is waiting in your playground.

### What you should already know

- **How the mesh works.** A proxy (the communications officer) sits beside every pod, and `istiod` (mission control) sends it orders. Every signal in or out of a pod goes through that proxy.
- **Kubernetes basics.** Namespaces, Deployments, Services, labels and `kubectl exec`.
- **A `VirtualService` helps.** It is Istio's own flight plan object. Much of the `HTTPRoute` object maps onto it field by field, so it is easier if you have written one before.

### What is in your playground

Your playground is a small training solar system: one `kind` cluster with **Istio 1.30.5** installed with Helm. It also has the **Gateway API objects installed**, because they are not part of Kubernetes or Istio. There is no Istio ingress gateway: in this module you build your own.

Two planets (namespaces) wait for you:

| Planet | What is on it |
| --- | --- |
| `starfleet` | The Starfleet: `bridge` (the flagship page), `cargo`, `navcom`, `scout` v1, v2 and v3, and `shuttle`, your test client |
| `outpost` | The `probe` v1 and v2, an echo service on port `8000`. It plays a second crew on another planet that wants to use your gate |

Every pod shows `2/2`: the app plus its communications officer (the `istio-proxy` sidecar). There is **no** `Gateway` and **no** `HTTPRoute` yet. Building them is your mission in this module.

The web paths inside the ships keep their original names: the bridge page lives at `/productpage`, and the scout answers at `/reviews/0`.

Launch your playground now, and keep it running next to you while you read the parts:

<!-- astrona:playground -->

## The parts of this module

The module has four parts, and three graded missions:

1. **Three Objects, Three Owners.** The three Gateway API objects, why they must be installed on their own, and what Istio adds when they are there.
2. **A Gateway That Creates Its Own Data Plane.** Create a `Gateway`, and watch Istio build a proxy for it in your own namespace. Then the mission: open a gate for a waiting route.
3. **Attach An HTTPRoute And Read Its Status.** Send signals through the gate, and read the status lights when a route is wrong. Then the mission: fix two broken routes.
4. **Decide Who May Dock.** Let a route from another namespace use your gate, on purpose. Then the mission: build a shared gate for two crews.
