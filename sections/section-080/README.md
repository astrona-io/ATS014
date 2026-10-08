# Configuring Ingress And Egress Traffic — Egress

Astronaut, in section 070 every spaceship (pod) sent its own signals straight out of the solar system (cluster). That gives you as many source addresses as you have nodes. The audit trail is spread across every communications officer's (sidecar's) log. And if a planet in another solar system wants a client certificate, every ship that calls it needs a copy.

An egress gateway pulls all of that into one place. Think of it as the solar system's **departure gate**: one checked exit that outgoing signals can be sent through. It is one standalone proxy. In this section you build the path to that gate, then move the TLS handshake onto it.

The most important idea comes in the first paragraph of module 1. Carry it into the exam: **an egress gateway intercepts nothing**. A signal reaches the gate only because a two-stage `VirtualService` (a flight plan) sent it there. A running egress gateway pod proves nothing at all.

**Curriculum item covered:** Configuring Ingress and Egress Traffic (egress half; the ingress half is section 060)

---

## What You Will Master

- The egress gateway as a standalone Envoy that carries only routed traffic, and why ingress and egress are not symmetric.
- The two-stage `VirtualService`: `gateways: [mesh]` for the sidecar stage, `gateways: [<gateway-name>]` for the gateway stage.
- `mesh` as the reserved name for all sidecars — the implicit default you have been using since section 010.
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

## The Learning Path

Work through the modules in this order, astronaut. For each one: read the parts with its playground open next to you, clean up the playground, then take its graded mission. Finish with the capstone, which brings the whole section together.

### 1. Route External Traffic Through An Egress Gateway
*   **Module Reader:** **[Route External Traffic Through An Egress Gateway](./module-01/course.md)**
    1. [A Gateway That Carries Nothing](./module-01/course-01-a-gateway-that-carries-nothing.md)
    2. [The Two-Stage `VirtualService`](./module-01/course-02-the-two-stage-virtualservice.md)
    3. [Restricting, Proving And The Trade-Off](./module-01/course-03-restricting-proving-and-the-trade-off.md)
*   **Hands-on Playground:** `sections/section-080/module-01/playground` — a kind cluster with Istio 1.30.5 (Helm) and an egress gateway `istio-egress` (label `istio: egress`) in namespace `istio-egress`; `bookinfo` with `curl` and `httpbin`. Needs outbound internet.
    ```bash
    astrona run --git ssh://git@github.com/astrona-io/ATS014.git -c sections/section-080/module-01/playground
    ```
*   **Practice Lab Sandbox:** **`sections/section-080/module-01/labs/lab-01`**
*   **Lab Run Command:**
    ```bash
    astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-080/module-01/labs/lab-01
    ```
*   **Hands-on Objective:** Route one external host through the gateway, prove the hop from the gateway's own log, then restrict the path with `sourceLabels` — and discover that the excluded workload still reaches the endpoint, directly.

### 2. TLS Origination At The Egress Gateway
*   **Module Reader:** **[TLS Origination At The Egress Gateway](./module-02/course.md)**
    1. [The Five-Step Chain](./module-02/course-01-the-five-step-chain.md)
    2. [Where The `DestinationRule` Attaches](./module-02/course-02-where-the-destinationrule-attaches.md)
    3. [Mutual TLS And The Consolidation Argument](./module-02/course-03-mutual-tls-and-consolidation.md)
*   **Hands-on Playground:** `sections/section-080/module-02/playground` — namespace `egwtls-demo`, the same shape, for building the full five-object chain.
    ```bash
    astrona run --git ssh://git@github.com/astrona-io/ATS014.git -c sections/section-080/module-02/playground
    ```
*   **Practice Lab Sandbox:** **`sections/section-080/module-02/labs/lab-01`**
*   **Lab Run Command:**
    ```bash
    astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-080/module-02/labs/lab-01
    ```
*   **Hands-on Objective:** Reach a TLS-only endpoint over plain `http://` with the gateway doing the handshake — and prove which proxy holds the TLS context by inspecting both.

### 3. Section Capstone Challenge
*   **Comprehensive Challenge:** **`sections/section-080/capstone/labs/lab-01` (One Exit, Two Partners)**
*   **Lab Run Command:**
    ```bash
    astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-080/capstone/labs/lab-01
    ```
*   **Hands-on Objective:** One gateway carrying two external hosts at once — one plain HTTP restricted by `sourceLabels`, one with TLS originated at the gateway — composing objects from sections 010, 030, 070 and both modules here.

---

The module playgrounds send signals to real hosts on the internet. Without outbound access you will see network errors, not mesh behaviour. **Every graded lab and the capstone in this section run entirely offline.**

Each playground is a training solar system and is ungraded: it spins up, prepares the environment, and waits. There is no task and no `astrona submit`. Tear one down with `astrona destroy <name>` when you are finished — the name is printed in each module's playground callout.
