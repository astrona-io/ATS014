# Scope Proxy Configuration With The Sidecar Resource

In a fresh Istio mesh, every sidecar proxy holds configuration for every Service in the mesh, whether or not its application ever calls that Service. The sidecar proxy is the Envoy container that Istio adds to each pod; all traffic in and out of the pod passes through it. `istiod`, Istio's control plane, builds that configuration and sends it to every proxy.

This default means routing works without any setup. But its cost grows with the size of the mesh, not with your application. The `Sidecar` resource is the Istio object that limits it: it tells `istiod` which hosts the proxies in a namespace, or in a few selected pods, need to know about.

The object itself is small, with four fields. This module covers what it changes inside the proxy, the short host syntax it uses, which `Sidecar` wins when several could apply, and what it can never do for you.

## Learning objectives

After this module you can:

- Describe what a proxy receives when no `Sidecar` exists, and explain why that scales badly.
- Explain how a configuration change reaches a running proxy, and why no pod restart is involved.
- Write a namespace-wide `Sidecar` that limits `egress.hosts`, using the `<namespace>/<host>` syntax correctly.
- Explain what `./*`, `*/*` and `istio-system/*` each select, and why `istio-system/*` belongs in almost every list.
- Predict what happens to a request for a host that is not in the proxy's configuration, under `ALLOW_ANY` and under `REGISTRY_ONLY`.
- Predict which `Sidecar` applies to a given pod, including selector precedence and the root default.
- Prove that a `Sidecar` took effect without sending any request.
- Explain why a `Sidecar` is not a security boundary, and name the objects to combine it with.

## Before you start

This module expects some knowledge, and a playground that is ready before the first hands-on step.

### What you should already know

- **How the mesh works.** A sidecar proxy runs in every meshed pod, and `istiod` sends it configuration. You can read that configuration with `istioctl proxy-config`.
- **Kubernetes basics.** Namespaces, Deployments, Services, pod labels and `kubectl exec`.

### What is in your playground

Your playground is one `kind` cluster with **Istio 1.30.5** already installed, and two namespaces, both with sidecar injection switched on:

| Namespace | Workload | What it does |
| --- | --- | --- |
| `starfleet` | `shuttle` | Test client pod; you send every test request from here |
| `starfleet` | `cargo` | Backend Service on port `9080` that returns item details |
| `outpost` | `probe` v1, v2 | HTTP echo server on Service port `8000` |

Every pod shows `2/2`: the application container plus its sidecar proxy. There is **no** `Sidecar` resource yet, and the mesh uses Istio's default outbound policy, `ALLOW_ANY`. Every proxy writes an access log.

Start your playground now, and keep it running while you read the parts:

<!-- astrona:playground -->

## The order of the parts

The module has four parts, a lab after the second part, a lab after the third part, and a summary at the end.

The first part measures what every proxy receives by default, shows how `istiod` delivers it over xDS, and explains why the cost grows with the mesh. The second part introduces the four fields of the `Sidecar` resource and the `<namespace>/<host>` syntax, and shows what happens to a request for a host that the proxy no longer knows. Its lab asks you to limit one namespace to the namespaces it calls.

The third part explains which `Sidecar` applies when a selector, a namespace and the root namespace each hold one, and why the winner replaces the others. Its lab asks you to repair a workload-selected `Sidecar` that lists too few hosts. The fourth part shows what a `Sidecar` cannot enforce, which objects do, and the order of checks to use when a host goes missing.
