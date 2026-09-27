# TLS Origination For External Services

<!-- astrona:playground -->
> [!NOTE]
> 🧪 **Hands-on playground for this module** — a clean, throwaway machine to explore on. No task, no grading. Folder: [`playground/`](https://github.com/astrona-io/ATS014/tree/main/sections/section-070/module-02/playground)
>
> ```sh
> astrona run --git ssh://git@github.com/astrona-io/ATS014.git -c sections/section-070/module-02/playground
> astrona destroy ats-014-playground-070-02
> ```

Module 1 registered an external host and immediately got timeouts, retries and routing for it. That worked because the traffic was plain HTTP on port 80, so the sidecar could read it.

Most real external services are HTTPS. When an application calls `https://api.example.com/`, the sidecar sees an encrypted TCP stream and nothing else: no method, no path, no headers, no status codes. Every layer-7 feature in this course is unavailable, and the access log has one line saying bytes moved.

TLS origination moves the encryption boundary. The application speaks plain HTTP to its own sidecar; the sidecar applies layer-7 rules in the clear; and **the sidecar** performs the TLS handshake with the external service. The bytes leaving the node are still HTTPS — nothing is less secure on the wire — but the mesh can now see and govern the request.

> TLS origination lets the app speak plain HTTP while the sidecar upgrades the connection to HTTPS.

## How this module is organised

1. **[Part 1 — Why HTTPS Is Opaque](./course-01-why-https-is-opaque.md)** — what the sidecar can and cannot see in an encrypted stream, and what that costs you.
2. **[Part 2 — The Three Objects](./course-02-the-three-objects.md)** — the `ServiceEntry` with two ports, the port redirect, and the `DestinationRule` that performs the handshake — plus the two placement details that break it.
3. **[Part 3 — Proving It, And Mutual TLS](./course-03-proving-it-and-mutual-tls.md)** — evidence from the destination's own view and from the proxy, what `MUTUAL` changes, and where this belongs relative to section 080.

## Learning objectives

After this module you can:

- Explain why an application making its own HTTPS calls is invisible to the mesh.
- Build the three objects TLS origination needs, and say what each contributes.
- Place `tls.mode: SIMPLE` under `portLevelSettings` for the right port, and explain what goes wrong otherwise.
- Explain what `sni` is and when omitting it breaks the handshake.
- Prove origination happened from the destination's own view of the request.
- Describe what changes for `MUTUAL`, and where the client certificate has to live.

## Before you start

You need `ServiceEntry` from module 1, `VirtualService` routing from section 010, and `DestinationRule.trafficPolicy` from section 030. This module is those three objects cooperating; none of them is new.

The playground gives you a single-node `kind` cluster with **Istio 1.30.5 already installed** (the `demo` profile) and the namespace **`tlsorig-demo`**, injected, with a `tester` client pod. No Istio configuration exists, and the mesh is at its `ALLOW_ANY` default — this module is about **visibility**, not permission.

The commands reach `httpbin.org`. **Without outbound internet access** you will see network errors rather than mesh behaviour.

## Where this fits

Origination here happens in the **client's own sidecar**, which means every workload calling the external service originates its own TLS — and any client certificate has to be available to every one of those pods. Section 080 module 2 moves the same operation to a dedicated egress gateway, so the certificate lives in one place. The objects are recognisably these ones with an extra hop, which is why this module comes first.
