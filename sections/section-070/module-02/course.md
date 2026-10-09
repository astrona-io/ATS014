# TLS Origination For External Services

An external service is a service that runs outside the mesh, for example a public API on the internet. Istio adds it to the mesh's service registry when you write a `ServiceEntry` for it. If the application calls it over plain HTTP, the sidecar proxy can read each request, so timeouts, retries and routing rules work for it.

Most external services only accept HTTPS. When an application calls `https://api.example.com/`, the application encrypts the request before the sidecar proxy receives it. The proxy then sees only encrypted bytes: no method, no path, no headers and no status code. Its access log gets one line that says bytes moved, and nothing more.

**TLS origination** moves the encryption into the proxy. TLS (Transport Layer Security) is the encryption protocol behind HTTPS. With TLS origination, the application sends a plain HTTP request to its own sidecar proxy. The proxy reads the request, applies your rules, and then opens a TLS connection to the external service. The request on the network is still HTTPS, but the mesh can now see and control every request.

## Learning objectives

After this module you can:

- Explain why the sidecar proxy cannot read an application's own HTTPS calls.
- Build the three objects that TLS origination needs, and say what each one does.
- Put `tls.mode: SIMPLE` under `portLevelSettings` for the right port, and explain what breaks otherwise.
- Explain what `sni` is and why you set it.
- Prove that TLS origination happened, from the external service's view and from the proxy's configuration.
- Describe what changes for `MUTUAL` TLS, and where the client certificate must be stored.

## What you need first

You should know three Istio objects and what each one does:

- A **`ServiceEntry`** adds a host outside the mesh to the mesh's service registry, so the proxies know its name and its ports.
- A **`VirtualService`** holds routing rules: it decides where a request goes, based on what the request contains.
- A **`DestinationRule`** holds the traffic policy for a destination: how a proxy connects to it, including TLS settings.

TLS origination uses these three objects together. None of them is new. Only the way they work together is new.

## Your playground

The playground is a single-node `kind` cluster with **Istio 1.30.5** installed. The namespace `starfleet` holds two workloads. The `shuttle` is a client pod with `curl`, and you send every test request from it. The `probe` is an HTTP echo server. Every pod in `starfleet` has a sidecar proxy (Envoy), and every proxy writes an access log, one line per request or connection.

No `ServiceEntry`, `VirtualService` or `DestinationRule` exists yet. The mesh uses its default outbound traffic policy, `ALLOW_ANY`, so pods may connect to any host outside the mesh.

The commands call `httpbin.org` on the internet. **Without outbound internet access you see network errors instead of mesh behaviour.** The graded labs do not need the internet, because their TLS service runs inside the cluster.

Start your playground now, and keep it running while you read the parts:

<!-- astrona:playground -->

## The parts

The module has four parts and a summary, in this order.

The first part, **Why The Proxy Cannot Read HTTPS Calls**, shows what the sidecar proxy can and cannot see when the application encrypts a request itself, and which Istio features stop working because of it.

The second part, **Originate TLS With Three Istio Objects**, builds the `ServiceEntry` with two ports, the `VirtualService` that moves requests from port `80` to port `443`, and the `DestinationRule` that turns on TLS. It adds one object at a time and shows the result of each.

The third part, **Troubleshoot Top-Level TLS And Double Encryption**, shows the two most common mistakes: TLS set on every port, and an application that still calls `https://`. The lab *Fix A Broken TLS Origination Lab* follows it.

The fourth part, **Verify TLS Origination And Configure Mutual TLS**, collects proof from the external service and from the proxy, adds a timeout to the external call, and explains what `MUTUAL` TLS changes. The lab *Originate TLS To A TLS-Only External Service Lab* follows it.

The **Summary** closes the module.
