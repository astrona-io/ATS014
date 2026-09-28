# Route External Traffic Through An Egress Gateway

<!-- astrona:playground -->
> [!NOTE]
> 🧪 **Hands-on playground for this module** — a clean, throwaway machine to explore on. No task, no grading. Folder: [`playground/`](https://github.com/astrona-io/ATS014/tree/main/sections/section-080/module-01/playground)
>
> ```sh
> astrona run --git ssh://git@github.com/astrona-io/ATS014.git -c sections/section-080/module-01/playground
> astrona destroy ats-014-playground-080-01
> ```

In section 070 every pod made its own outbound connection. That works, and for many clusters it is the right answer. It also means outbound traffic leaves from as many source IPs as you have nodes, the audit trail is spread across every sidecar's logs, and a partner who wants to allow-list your address has nothing single to allow-list.

An egress gateway concentrates that. It is the same standalone Envoy as the ingress gateway, pointed the other way: sidecars send external traffic to it, and it makes the outbound connection. One exit point, one place to audit, one source address.

The single most important thing to understand before any YAML:

> An egress gateway **intercepts nothing**. Traffic reaches it because you routed it there, explicitly, in a `VirtualService` with two stages.

## How this module is organised

1. **[A Gateway That Carries Nothing](./course-01-a-gateway-that-carries-nothing.md)** — what is already running, why it is idle, and the `Gateway` object with its counter-intuitive host list.
2. **[The Two-Stage `VirtualService`](./course-02-the-two-stage-virtualservice.md)** — one object holding two rule sets that run in two different proxies, and the reserved `mesh` name that separates them.
3. **[Restricting, Proving And The Trade-Off](./course-03-restricting-proving-and-the-trade-off.md)** — `sourceLabels`, the evidence that the hop happened, what you gain and pay, and the module's pitfalls.

## Learning objectives

After this module you can:

- Explain why a running egress gateway carries no traffic until routing sends it there.
- Write the two-stage `VirtualService` and say which proxy each stage runs in.
- Explain what `gateways: [mesh]` means and why the `Gateway` object lists the **external** hostname.
- Explain the conventional empty-subset `DestinationRule` on the gateway's own Service.
- Restrict which workloads take the egress path with `sourceLabels`, and say what that does and does not enforce.
- Prove a request traversed the gateway, from the gateway's log and the sidecar's route.
- State the operational trade-off in both directions.

## Before you start

You need `ServiceEntry` from section 070 module 1, and the `Gateway` plus `VirtualService` pairing from section 060 module 1. This module is those two ideas joined, which is why it comes after both.

The playground gives you a single-node `kind` cluster with **Istio 1.30.5 already installed** (the `demo` profile, which includes **`istio-egressgateway`** in `istio-system`) and the namespace **`egwgw-demo`**, injected, with a `tester` client pod. The mesh is at its `ALLOW_ANY` default. No `ServiceEntry`, `Gateway` or `VirtualService` exists.

The commands reach `httpbin.org`; **without outbound internet access** you will see network errors rather than mesh behaviour.

## Where this fits

This module routes traffic through the gateway; module 2 moves the TLS handshake onto it, which is where the arrangement starts to pay for itself. Both depend on section 070's `ServiceEntry` — without the host in the registry there is nothing for either stage to route.
