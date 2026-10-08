# Route External Traffic Through An Egress Gateway

<!-- astrona:playground -->
> [!NOTE]
> 🧪 **Hands-on playground for this module** — a clean, throwaway machine to explore on. No task, no grading. Folder: `playground/`
>
> ```sh
> astrona run --git ssh://git@github.com/astrona-io/ATS014.git -c sections/section-080/module-01/playground
> astrona destroy ats-014-playground-080-01
> ```

Welcome to a new mission, astronaut. In section 070 every spaceship (pod) sent its own signals out of the solar system (cluster). That works, and for many clusters it is the right answer. But it also means outgoing signals leave from as many source IPs as you have nodes. The audit trail is spread across every sidecar's log. And a partner planet that wants to allow-list your address has no single address to allow-list.

An egress gateway pulls all of that into one place. Think of it as the solar system's departure gate: one checked exit that all outgoing signals can be sent through. It is the same standalone Envoy as the ingress gateway, pointed the other way. Sidecars send external signals to it, and it makes the outbound connection. One exit, one place to audit, one source address.

The single most important thing to understand before any YAML:

> An egress gateway **intercepts nothing**. A signal reaches it only because your flight plan, a `VirtualService` with two stages, sent it there.

## How this module is organised

1. **[A Gateway That Carries Nothing](./course-01-a-gateway-that-carries-nothing.md)** — what is already running, why it is idle, where it lives on a Helm or demo-profile install, and the `Gateway` object with its counter-intuitive host list.
2. **[The Two-Stage `VirtualService`](./course-02-the-two-stage-virtualservice.md)** — one object holding two rule sets that run in two different proxies, the reserved `mesh` name that separates them, and `tls:` routes for HTTPS that passes through still encrypted.
3. **[Restricting, Proving And The Trade-Off](./course-03-restricting-proving-and-the-trade-off.md)** — the evidence that the hop happened, the mistakes that hide behind a `200`, `sourceLabels`, what you gain and pay, and the module's pitfalls.

## Learning objectives

After this module you can:

- Explain why a running egress gateway carries no traffic until routing sends it there.
- Write the two-stage `VirtualService` and say which proxy each stage runs in.
- Route HTTPS traffic through the gateway unopened, with `tls.mode: PASSTHROUGH` and `tls:` routes on `sniHosts`.
- Explain what `gateways: [mesh]` means and why the `Gateway` object lists the **external** hostname.
- Explain the conventional empty-subset `DestinationRule` on the gateway's own Service.
- Restrict which workloads take the egress path with `sourceLabels`, and say what that does and does not enforce.
- Prove a request traversed the gateway, from the gateway's log and the sidecar's route.
- State the operational trade-off in both directions.

## Before you start

This module assumes [section 000](../../section-000/module-01/course.md): a proxy beside every pod, `istiod` programming it over xDS, and `istioctl proxy-config` as the way to see what a proxy actually holds rather than what you hoped it holds.

You need `ServiceEntry` from section 070 module 1, and the `Gateway` plus `VirtualService` pairing from section 060 module 1. This module is those two ideas joined, which is why it comes after both.

The playground gives you a single-node `kind` cluster with **Istio 1.30.5** installed with Helm: `istio-base`, `istiod`, and an **egress gateway** — Helm release `istio-egress` in namespace `istio-egress`, pods labelled `istio: egress`, Service type `ClusterIP`. It is running and carries no traffic. The mesh is at its `ALLOW_ANY` default. The namespace **`bookinfo`** is injected and holds a `curl` client pod and `httpbin` (port `8000`), with mesh-wide access logs on. No `ServiceEntry`, `Gateway` or `VirtualService` exists.

Before the first "Try it", paste these helpers into your terminal. The first sends a request (by default to `https://httpbin.org/get`). The other two print the newest access-log line of each hop:

```sh
call_external() { kubectl exec -n bookinfo deploy/curl -- curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" --max-time 10 "${1:-https://httpbin.org/get}"; echo "  exit=$?"; }
log_hop1_sidecar() { kubectl logs -n bookinfo deploy/curl -c istio-proxy --tail=1; }     # curl's sidecar
log_hop2_egress() { kubectl logs -n istio-egress deploy/istio-egress --tail=1; }        # egress gateway
```

A shell function lasts for one terminal, so paste them again in each new one.

The graded lab for this module runs in its own environment: a `demo`-profile install, where the gateway is `istio-egressgateway` in `istio-system` (label `istio: egressgateway`), namespace `egwgw-demo`, and plain-HTTP traffic. Part 1 and Part 2 show both sets of names side by side.

The commands reach `httpbin.org`; **without outbound internet access** you will see network errors rather than mesh behaviour.

## Where this fits

This module routes signals through the departure gate. Module 2 moves the TLS handshake onto it, and that is where the arrangement starts to pay for itself. Both depend on section 070's `ServiceEntry` — without the host in the registry there is nothing for either stage to route.
