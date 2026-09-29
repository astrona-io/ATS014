# Ingress With The Kubernetes Gateway API

<!-- astrona:playground -->
> [!NOTE]
> 🧪 **Hands-on playground for this module** — a clean, throwaway machine to explore on. No task, no grading. Folder: [`playground/`](https://github.com/astrona-io/ATS014/tree/main/sections/section-060/module-03/playground)
>
> ```sh
> astrona run --git ssh://git@github.com/astrona-io/ATS014.git -c sections/section-060/module-03/playground
> astrona destroy ats-014-playground-060-03
> ```

Module 2 ended on a complaint: the `Ingress` API can express a host and a path and nothing else, so every controller invented its own annotations and none of them are portable.

The **Gateway API** is the Kubernetes project's answer. It is a set of CRDs — not part of core Kubernetes — and Istio implements it. It has real fields for the things `Ingress` needed annotations for, it separates cluster infrastructure from application routing so different teams can own different objects, and it makes cross-namespace attachment explicit instead of assumed.

One warning before any YAML: this module's `Gateway` is **not** module 1's `Gateway`. Same kind name, different API group, genuinely different behaviour. Keeping them apart is half the work.

## How this module is organised

1. **[Three Objects, Three Owners](./course-01-three-objects-three-owners.md)** — `GatewayClass`, `Gateway` and `HTTPRoute`, why the CRDs must be installed separately, and the role split the design is built around.
2. **[A Gateway That Creates Its Own Data Plane](./course-02-a-gateway-that-creates-its-own-data-plane.md)** — the difference from `networking.istio.io/Gateway`, where the proxy pod appears, and `allowedRoutes` as deny-by-default attachment.
3. **[`HTTPRoute`, Status And What Stays In Istio](./course-03-httproute-status-and-what-stays-in-istio.md)** — translating a `VirtualService` field by field, reading `Accepted` / `Programmed` / `ResolvedRefs`, and the Istio features that have no Gateway API equivalent.

## Learning objectives

After this module you can:

- Name the three Gateway API objects and say what each one owns.
- Explain why `no matches for kind "Gateway"` is not an Istio error.
- Explain how a Gateway API `Gateway` differs from `networking.istio.io/Gateway`, including where the proxy pod ends up.
- Control cross-namespace attachment with `allowedRoutes`, and diagnose a route that is not accepted.
- Write an `HTTPRoute` with `parentRefs`, `hostnames`, `matches` and `backendRefs`, and translate a `VirtualService` into it.
- Read `Accepted`, `Programmed` and `ResolvedRefs` conditions to tell a configuration error from an infrastructure one.
- List what stays an Istio object even when routing is done with the Gateway API.

## Before you start

This module assumes [section 000](../../section-000/module-01/course.md): a proxy beside every pod, `istiod` programming it over xDS, and `istioctl proxy-config` as the way to see what a proxy actually holds rather than what you hoped it holds.

You need module 1 of this section — listeners, host-based routing and the 404/503 split are the same ideas — and it helps to have `VirtualService` fresh, because much of this module is a translation exercise.

The playground gives you a single-node `kind` cluster with **Istio 1.30.5 already installed** (the `demo` profile), the **Gateway API CRDs installed** by the bootstrap script, and the namespace **`gwapi-demo`**, injected, containing `booking-service` on port 80. No `Gateway` and no `HTTPRoute` exist yet.

The CRD version the playground pins is set in `playground/bootstrap/prepare.sh`. Gateway API and Istio release on their own schedules, so check the Istio release notes for the version pairing rather than assuming any particular pin is current.

## Where this fits

This is the third and last of the section's three ingress APIs, and the one to reach for in new work where it is available. It does not replace Istio's own objects wholesale: everything on the `DestinationRule` side — subsets, load balancer policy, connection pools, outlier detection — and Istio's retries, timeouts, mirroring and fault injection remain Istio objects and continue to apply to traffic routed by an `HTTPRoute`. Part 3 draws that line explicitly.
