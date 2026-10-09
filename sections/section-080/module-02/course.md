# TLS Origination At The Egress Gateway

Astronaut, some planets in other solar systems only take sealed signals. They speak HTTPS, which is HTTP inside a lock called **TLS** (Transport Layer Security). Some of them go further and ask every caller to show a **client certificate**: an ID card that proves who is calling.

Your ships do not have to deal with any of that. A ship can send a plain `http://` signal, and a proxy on the way can put the lock on for it. Starting the TLS connection on behalf of the app is called **TLS origination**. In this module the proxy that does it is the **egress gateway**, the solar system's **departure gate**: one checked exit that outgoing signals fly through.

Why the gate, and not each ship's own communications officer (the sidecar)? Because of the ID card. If the sidecars do the handshake, every ship that calls the partner needs a copy of the client certificate. That is one secret on dozens of ships, renewed in dozens of places, and readable by anyone who breaks into any of them. Move the handshake to the gate, and the certificate lives in exactly one place.

> The departure gate receives plain HTTP from your ships and sends TLS to the outside planet. The `DestinationRule` that adds the lock names the **outside host**, and it is followed by the gate, because the gate is the proxy that calls that host.

## Learning objectives

After this module you can:

- Name the five objects of the chain and the job of each one.
- Explain why the gate listens on port `80` but sends to port `443`, and what happens when the onward route uses the wrong port.
- Originate TLS at the gate with a `DestinationRule` on the outside host, using `portLevelSettings` and `sni`.
- Prove which proxy holds the TLS settings by comparing the gate's and the sidecar's clusters with `istioctl proxy-config`.
- Keep the TLS settings off the sidecars with `exportTo`.
- Present a client certificate with `tls.mode: MUTUAL` and `credentialName`.
- Name the namespace the certificate's `Secret` must live in, and find a missing one with `istioctl proxy-config secret` and the logs.
- Weigh origination at the gate against origination in every sidecar.

## Before you start

Every mission starts with a pre-flight check, astronaut. Check what you should already know, see what waits in your playground, and paste a few helpers into your terminal.

### What you should already know

- **How the mesh works.** A proxy (the communications officer) sits beside every pod, and `istiod` (mission control) sends it orders. You can read those orders with `istioctl proxy-config`.
- **The `ServiceEntry`.** It adds a planet from another solar system to the star chart, so the mesh can route to it.
- **The two-stage route through the gate.** One `VirtualService` holds two rules. The rule for `mesh` runs in every sidecar and sends the signal to the gate. The rule for the gate's `Gateway` runs in the gate and sends it on to the outside host. A `DestinationRule` on the gate's own Service gives stage 1 an empty subset to name.

### What is in your playground

Your playground is a small training solar system: one `kind` cluster with **Istio 1.30.5** installed with Helm. Next to `istio-base` and `istiod`, it runs an **egress gateway**:

| What | Where |
| --- | --- |
| Helm release and namespace | `istio-egress` in the namespace `istio-egress` |
| Deployment and Service | `istio-egress`, Service type `ClusterIP`, ports `80` and `443` |
| Pod label a `Gateway` selects | `istio: egress` |

The gate is running and carries **no** traffic. Mission control also has **DNS capture** switched on: a ship can look up a host from a `ServiceEntry` by its name, and its sidecar answers the lookup. Your ships live on two planets:

| Planet and ship | Its role |
| --- | --- |
| `starfleet` / `shuttle` | **Your shuttle**. You send every test signal from here, with the `curl` command. It shows `2/2`: the app plus its communications officer |
| `starfleet` / Secret `partner-client-cert` | The **client certificate** a partner handed over. You need it in the last parts |
| `outpost` / `partner` | A **partner server** outside the mesh (no sidecar). It only answers HTTPS, and only to callers that show a client certificate it trusts |

Mesh-wide access logs are on, so the shuttle's sidecar **and** the gate each write one line per signal into their flight log. There is no `ServiceEntry`, `Gateway`, `DestinationRule` or `VirtualService` yet.

> [!WARNING]
> **The first parts need outbound internet access.** They call `httpbin.org` from inside the cluster. Without internet access you see network failures, not mesh decisions. Run a plain `curl https://httpbin.org/get` on your own machine first. The partner server and the graded missions do **not** need internet access.

Launch your playground now, and keep it running next to you while you read the parts:

<!-- astrona:playground -->

### Helpers to paste first

Paste these into each new terminal. `call_httpbin` sends one plain `http://` signal from the shuttle to `httpbin.org/get` and prints the address `httpbin.org` says it was called on, plus the status code. `call_partner` does the same for the partner server. The other two print the newest line of each flight log: the shuttle's sidecar, and the gate.

```sh
call_httpbin() { kubectl exec -n starfleet deploy/shuttle -- curl -s --max-time 15 -w "\n%{http_code}\n" http://httpbin.org/get | grep -E '"url"|^[0-9]{3}$'; }
call_partner() { kubectl exec -n starfleet deploy/shuttle -- curl -s --max-time 10 -w "%{http_code}\n" http://partner.outpost.example/; }
log_shuttle() { sleep 2; kubectl logs -n starfleet deploy/shuttle -c istio-proxy --tail=1; }
log_gate() { sleep 2; kubectl logs -n istio-egress deploy/istio-egress --tail=1; }
```

`httpbin.org` answers with the full address it was called on, so the start of its `url` field tells you how the signal arrived: `http://` for plain, `https://` for sealed.

## Why this matters

Partner APIs that ask for a client certificate are common, and the exam expects you to wire them up by hand. The configuration is small: one object moves to a new host, and one port number changes. But each piece sits on a different proxy, and a mistake often still returns an answer. This module trains you to prove where the lock is put on, not just to see a `200`.
