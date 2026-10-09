# Configuring Ingress And Egress Traffic — Egress

Astronaut, without an egress gateway every spaceship (pod) sends its own signals straight out of the solar system (cluster). That gives you as many source addresses as you have nodes. The audit trail is spread across every communications officer's (sidecar's) log. And if a planet in another solar system wants a client certificate, every ship that calls it needs a copy.

An egress gateway pulls all of that into one place. Think of it as the solar system's **departure gate**: one checked exit that outgoing signals can be sent through. It is one standalone proxy. In this section you build the path to that gate, then move the TLS handshake onto it.

The most important idea of this section comes first. Carry it into the exam: **an egress gateway intercepts nothing**. A signal reaches the gate only because a two-stage `VirtualService` (a flight plan) sent it there. A running egress gateway pod proves nothing at all.

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

Work through the modules in this order. Each part teaches one idea. A mission (a graded lab) comes right after the part it practises, and the last page of each module is a wrap-up. The capstone at the end uses everything in the section at once.

### [Route External Traffic Through An Egress Gateway](module-01/course.md)

5 parts and 2 missions:

1. [A Gateway That Carries Nothing](module-01/course-01-a-gateway-that-carries-nothing.md)
2. [Open The Departure Gate](module-01/course-02-open-the-departure-gate.md)
3. [The Two-Stage `VirtualService`](module-01/course-03-the-two-stage-virtualservice.md)
4. [Prove The Hop, And Break It](module-01/course-04-prove-the-hop-and-break-it.md)
   - Mission: [Repair The Departure Gate Lab](module-01/labs/lab-02/question.md)
5. [Choose Who Flies Through The Gate](module-01/course-05-choose-who-flies-through-the-gate.md)
   - Mission: [Send One Ship Through The Departure Gate Lab](module-01/labs/lab-01/question.md)
6. [Wrap-Up: Mission Debrief](module-01/course-06-wrap-up.md)

### [TLS Origination At The Egress Gateway](module-02/course.md)

5 parts and 2 missions:

1. [The Five-Step Chain](module-02/course-01-the-five-step-chain.md)
2. [Originate TLS At The Gate](module-02/course-02-originate-tls-at-the-gate.md)
3. [Where The `DestinationRule` Attaches](module-02/course-03-where-the-destinationrule-attaches.md)
   - Mission: [Lock The Signal At The Departure Gate Lab](module-02/labs/lab-01/question.md)
4. [A Partner That Checks IDs](module-02/course-04-a-partner-that-checks-ids.md)
5. [Hand The Gate Its Keys](module-02/course-05-hand-the-gate-its-keys.md)
   - Mission: [Open The Partner's Locked Door Lab](module-02/labs/lab-02/question.md)
6. [Wrap-Up: Mission Debrief](module-02/course-06-wrap-up.md)

### Capstone

Your final mission for this section: **[One Exit, Two Partners Capstone Lab](capstone/labs/lab-01/README.md)**.

---

<!-- astrona:playground:environment-explain -->
