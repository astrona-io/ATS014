# Control External Access With ServiceEntry

<!-- astrona:playground -->
> [!NOTE]
> 🧪 **Hands-on playground for this module** — a clean, throwaway machine to explore on. No task, no grading. Folder: [`playground/`](https://github.com/astrona-io/ATS014/tree/main/sections/section-070/module-01/playground)
>
> ```sh
> astrona run --git ssh://git@github.com/astrona-io/ATS014.git -c sections/section-070/module-01/playground
> astrona destroy ats-014-playground-070-01
> ```

Every workload you have configured so far talked to another workload in the mesh. Real applications also talk *out*: a payment API, an object store, a partner's endpoint, a package registry. Those destinations are not in the Kubernetes service registry, which means Istio knows nothing about them — it cannot route them, cannot time them out, cannot report on them, and by default does not stop them either.

A `ServiceEntry` adds an external host to the mesh registry. Once a host is in the registry it stops being special: the `VirtualService` and `DestinationRule` behaviour from every earlier section applies to it exactly as it does to an in-cluster Service.

## How this module is organised

1. **[The Outbound Traffic Policy](./course-01-the-outbound-traffic-policy.md)** — the mesh-wide setting that decides whether unknown destinations are allowed at all, and the 502 that identifies a refusal.
2. **[The `ServiceEntry` Object](./course-02-the-serviceentry-object.md)** — the four fields that matter, what each decides, and why the declared protocol is the one that unlocks everything else.
3. **[A Registered Host Is An Ordinary Host](./course-03-a-registered-host-is-an-ordinary-host.md)** — applying `VirtualService` and `DestinationRule` to somebody else's API, `exportTo` scope, the `Sidecar` interaction, and the module's pitfalls.

## Learning objectives

After this module you can:

- Explain `meshConfig.outboundTrafficPolicy.mode` and the difference between `ALLOW_ANY` and `REGISTRY_ONLY`.
- Recognise the response a blocked destination produces, and tell it apart from a network failure.
- Write a `ServiceEntry` for an external host, choosing correct `location` and `resolution` values.
- Explain why the declared `protocol` decides whether layer-7 features are available.
- Apply a `VirtualService` timeout and a `DestinationRule` policy to an external host.
- Scope a `ServiceEntry` with `exportTo`, and diagnose the case where a `Sidecar` resource hides one.

## Before you start

You need `VirtualService` from section 010 and the `timeout` field from section 040 — the last part of this module reuses both against an external host. Section 010's `Sidecar` resource matters for the final pitfall.

The playground gives you a single-node `kind` cluster with **Istio 1.30.5 already installed** (the `demo` profile, so `outboundTrafficPolicy.mode` is at its `ALLOW_ANY` default) and the namespace **`egress-demo`**, injected, containing a `tester` client pod with `curl`. No `ServiceEntry` exists.

The commands below reach real hosts on the internet (`httpbin.org`, `example.com`). **If your environment has no outbound internet access**, what you see will be network failures rather than mesh decisions — check a plain `curl` from the node before concluding Istio did something.

## Where this fits

This is the foundation for the rest of the external-traffic material. Module 2 uses a `ServiceEntry` to make an HTTPS service visible to the mesh; module 3 uses the same object with a different `location` to bring a non-Kubernetes workload of your own into it; and section 080's egress gateway routes traffic to hosts that a `ServiceEntry` registered. Get this object right and those three are variations on it.
