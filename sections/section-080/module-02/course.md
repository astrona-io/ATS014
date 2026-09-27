# TLS Origination At The Egress Gateway

<!-- astrona:playground -->
> [!NOTE]
> 🧪 **Hands-on playground for this module** — a clean, throwaway machine to explore on. No task, no grading. Folder: [`playground/`](https://github.com/astrona-io/ATS014/tree/main/sections/section-080/module-02/playground)
>
> ```sh
> astrona run --git ssh://git@github.com/astrona-io/ATS014.git -c sections/section-080/module-02/playground
> astrona destroy ats-014-playground-080-02
> ```

This module is the last two joined: the egress gateway from module 1, doing the TLS origination from section 070 module 2.

The reason to combine them is **credentials**. Sidecar-side origination works, but if the external service requires a client certificate, every pod that calls it needs that certificate — a secret distributed to dozens of workloads, rotated in dozens of places, and readable by anything that compromises any of them. Move the handshake to the gateway and the certificate lives in exactly one place.

The change to the configuration is smaller than you might expect. One object moves, and one port number changes.

## How this module is organised

1. **[Part 1 — The Five-Step Chain](./course-01-the-five-step-chain.md)** — the full path with the owner of each step, and the two lines where the mistakes live.
2. **[Part 2 — Where The `DestinationRule` Attaches](./course-02-where-the-destinationrule-attaches.md)** — why traffic policy follows the calling proxy, and how to prove which proxy holds the TLS context.
3. **[Part 3 — Mutual TLS And The Consolidation Argument](./course-03-mutual-tls-and-consolidation.md)** — `credentialName` and the namespace it is read from, the sidecar-versus-gateway comparison, and the module's pitfalls.

## Learning objectives

After this module you can:

- Trace a request through the full chain: application, sidecar, egress gateway, external service.
- Place the origination `DestinationRule` on the correct host so the gateway performs the handshake.
- Explain why the gateway-side route targets port 443 while the listener stays on 80.
- Prove which proxy holds the TLS context by comparing both proxies' configuration.
- Configure `MUTUAL` with `credentialName` and name the namespace the secret must live in.
- State the operational argument for gateway origination over sidecar origination.

## Before you start

You need both predecessors: TLS origination (section 070, module 2) and the two-stage egress `VirtualService` (module 1 of this section). This module assumes you can write each from memory.

The playground gives you a single-node `kind` cluster with **Istio 1.30.5 already installed** (the `demo` profile, including `istio-egressgateway`) and the namespace **`egwtls-demo`**, injected, with a `tester` client pod. No Istio configuration exists, and the mesh is at its `ALLOW_ANY` default.

The commands reach `httpbin.org`; **without outbound internet access** you will see network errors rather than mesh behaviour.

## Where this fits

This is the last module of the course, and it is the one that composes the most: a `ServiceEntry` from section 070, a `Gateway` and a two-stage `VirtualService` from module 1, and a `DestinationRule` with `portLevelSettings` from section 030's precedence rules. If the five objects below make sense to you without looking anything up, the traffic-management domain is done.
