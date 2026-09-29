# Scope Proxy Configuration With The Sidecar Resource

<!-- astrona:playground -->
> [!NOTE]
> 🧪 **Hands-on playground for this module** — a clean, throwaway machine to explore on. No task, no grading. Folder: [`playground/`](https://github.com/astrona-io/ATS014/tree/main/sections/section-010/module-02/playground)
>
> ```sh
> astrona run --git ssh://git@github.com/astrona-io/ATS014.git -c sections/section-010/module-02/playground
> astrona destroy ats-014-playground-010-02
> ```

Ask a sidecar in a fresh mesh what it knows about, and the answer is: everything. Every Service in every namespace, whether or not the pod beside it will ever send a single request there. That is a deliberate default — it means routing works without declaring anything — and it has a cost that grows with the cluster rather than with your application.

`Sidecar` is the object that cuts it down. It is the only `networking.istio.io` resource in this course that is about the proxy's **configuration** rather than about a request's journey, and the thing you measure is not a response code but the size of a config dump.

> Every sidecar knows about every service by default; the `Sidecar` resource is how you cut that down.

It earns three parts because the interesting material is not the YAML — the object has four fields — but the mechanism it controls, the small host language it uses, and a precedence model that silently breaks a namespace if you get it wrong.

## How this module is organised

1. **[What A Proxy Is Programmed With](./course-01-what-a-proxy-is-programmed-with.md)** — the service registry, how it becomes clusters and listeners in every proxy, and why the cost of that scales with the cluster rather than with your workload.
2. **[The Sidecar Object And Its Host Language](./course-02-the-sidecar-object-and-host-language.md)** — `workloadSelector`, `egress.hosts` and the `<namespace>/<host>` syntax, including why `istio-system/*` is boilerplate rather than a choice.
3. **[Precedence, Reachability And What It Is Not](./course-03-precedence-reachability-and-limits.md)** — which `Sidecar` applies to a workload when several could, why removing config removes reachability, and why this is not a security boundary.

## Learning objectives

After this module you can:

- Describe what a sidecar is programmed with when no `Sidecar` resource exists, and explain why that scales badly.
- Explain how a configuration change is delivered to a running proxy, and why no pod restart is involved.
- Write a namespace-wide `Sidecar` limiting `egress.hosts`, using the `<namespace>/<host>` syntax correctly.
- Explain what `./*`, `*/*` and `istio-system/*` each select, and why the last is near-mandatory.
- Predict which `Sidecar` applies to a given workload, including the root-namespace default and selector precedence.
- Prove a scoping change took effect without sending any traffic.
- State why `Sidecar` controls proxy configuration rather than network reachability, and name what to combine it with for enforcement.

## Before you start

This module leans harder on [section 000](../../section-000/module-01/course.md) than any other in this section: the service registry, the xDS push, and reading a proxy's cluster and listener dumps are not background here — they are the thing being changed. If `istioctl proxy-config cluster` is not yet a command you can read, start there.

It also helps to have the `VirtualService` / `DestinationRule` pair from Module 1 fresh — not because this object depends on them, but because "the proxy was never told about that host" is a failure mode you will now be able to tell apart from "the routing rule did not match".

The playground gives you a single-node `kind` cluster with **Istio 1.30.5 already installed** (the `demo` profile) and two injected namespaces, which is the minimum for scoping to have anything visible to do:

- **`sidecar-demo`** — a `tester` client pod with `curl`.
- **`sidecar-other`** — an `httpbin` Deployment and Service on port 8000.

No `Sidecar` resource exists yet.

## Where this fits

Everything else in this course adds configuration to proxies. This module is the one that takes it away, and that makes it the counterweight to the rest: a mesh with a thousand services and no scoping is a mesh where every proxy carries a thousand services' worth of state and re-reads it whenever anything changes. It is also a quiet cause of failures in later sections — a perfectly correct `ServiceEntry` in section 070 can be invisible to one namespace because a `Sidecar` scoped it away, and the symptom is the same 502 you would get from never having registered the host at all.
