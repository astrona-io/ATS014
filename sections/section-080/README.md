# Configuring Ingress And Egress Traffic — Egress

Without an egress gateway, every pod sends its own requests straight out of the cluster. That gives you as many source addresses as you have nodes. The record of outbound traffic is spread across the log of every sidecar proxy. And if an outside service asks for a client certificate, every pod that calls it needs a copy.

An **egress gateway** pulls all of that into one place. It is a standalone Envoy proxy that outbound requests can be sent through, so traffic leaves the mesh at one point. In this section you build the route to the egress gateway, then move the TLS handshake onto it.

The most important idea of this section comes first. Carry it into the exam: **an egress gateway intercepts nothing**. A request reaches the egress gateway only because a two-stage `VirtualService` sent it there. A running egress gateway pod proves nothing at all.

**Curriculum item covered:** Configuring Ingress and Egress Traffic (the egress half)

---

## What You Will Master

- The egress gateway as a standalone Envoy that carries only routed traffic, and why ingress and egress are not symmetric.
- The two-stage `VirtualService`: `gateways: [mesh]` for the sidecar stage, `gateways: [<gateway-name>]` for the gateway stage.
- `mesh` as the reserved name for all sidecars — the implicit default every `VirtualService` without `gateways:` already uses.
- Why the `Gateway`'s `servers[].hosts` carries the **external** hostname, read from the gateway's point of view.
- The conventional label-less `DestinationRule` subset on the gateway's own Service, and what it is actually for.
- `sourceLabels` restricting which workloads take the egress path — a route filter, not a permission, and what "un-diverted" means.
- Proving the hop from the gateway's own access log, with caller attribution, and from the sidecar's rewritten route.
- The full five-step chain with TLS origination, and why the gateway receives on one port and sends on 443.
- Why the origination `DestinationRule` targets the **external host**: traffic policy is applied by the proxy that calls the destination.
- The `transportSocket` comparison across both proxies — the most compact proof that policy follows the caller.
- `MUTUAL` with `credentialName`, read from the **gateway's** namespace, and the failure when the secret is elsewhere.
- The operational trade-off in both directions, and the consolidation argument that decides it for client certificates.

---

## Modules In This Section

Work through the modules in this order. Each part teaches one idea. A graded lab comes right after the part it practises, and the last page of each module is a summary. The capstone lab at the end uses everything in the section at once.

### Route External Traffic Through An Egress Gateway

5 parts and 2 labs:

1. Why An Egress Gateway Carries No Traffic By Itself
2. Write The Egress `Gateway` And Its `DestinationRule`
3. Write The Two-Stage `VirtualService`
4. Prove The Egress Hop And Diagnose Broken Routes
   - Lab: Fix An Egress Route That Skips The Gateway Lab
5. Limit The Egress Route With `sourceLabels`
   - Lab: Route One Workload Through The Egress Gateway Lab
6. Summary

### TLS Origination At The Egress Gateway

5 parts and 2 labs:

1. The Five-Step Chain
2. Originate TLS At The Gate
3. Where The `DestinationRule` Attaches
   - Lab: Lock The Signal At The Departure Gate Lab
4. A Partner That Checks IDs
5. Hand The Gate Its Keys
   - Lab: Open The Partner's Locked Door Lab
6. Wrap-Up: Mission Debrief

### Capstone

The section ends with a capstone lab that uses everything in it: **One Exit, Two Partners Capstone Lab**.

---

<!-- astrona:playground:environment-explain -->
