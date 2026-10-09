# TLS Origination At The Egress Gateway

Many servers outside the cluster only accept HTTPS: HTTP sent inside a **TLS** (Transport Layer Security) connection, which encrypts the traffic and proves the server's identity with a certificate. Some of these servers go further. They ask every caller for a **client certificate**, a certificate that proves who is calling.

Your applications do not have to handle any of this. An application can send plain `http://`, and a proxy on the way can open the TLS connection for it. Starting the TLS connection on behalf of the application is called **TLS origination**. In this module the proxy that does it is the **egress gateway**: an Envoy proxy at the edge of the mesh that outgoing traffic passes through before it leaves the cluster.

Why the egress gateway, and not the sidecar proxy in each pod? The reason is the client certificate. If the sidecar proxies do the TLS handshake, every workload that calls the server needs a copy of the client certificate and its private key. That is one secret in many namespaces, renewed in many places, and readable by anyone who breaks into any of those pods. When the egress gateway does the handshake, the certificate lives in exactly one place.

The whole module rests on one fact. The egress gateway receives plain HTTP from the sidecar proxies and sends TLS to the external host. The `DestinationRule` that turns on TLS names the **external host**, and the egress gateway applies it, because the egress gateway is the proxy that calls that host.

## Learning objectives

After this module you can:

- Name the five objects that route a request through the egress gateway with TLS origination, and the job of each one.
- Explain why the egress gateway listens on port `80` but sends to port `443`, and what happens when the second routing rule uses the wrong port.
- Originate TLS at the egress gateway with a `DestinationRule` on the external host, using `portLevelSettings` and `sni`.
- Prove which proxy holds the TLS settings by comparing the clusters of the egress gateway and of the sidecar proxy with `istioctl proxy-config`.
- Keep the TLS settings off the sidecar proxies with `exportTo`.
- Present a client certificate with `tls.mode: MUTUAL` and `credentialName`.
- Name the namespace the certificate's `Secret` must live in, and find a missing one with `istioctl proxy-config secret` and the logs.
- Compare TLS origination at the egress gateway with TLS origination in every sidecar proxy.

## Before you start

This module builds on routing through an egress gateway. It expects some knowledge, and a playground that is ready before the first hands-on step.

### What you should already know

- **How the mesh works.** A sidecar proxy (Envoy) runs next to the application in every pod of the mesh, and all traffic of the pod passes through it. `istiod`, Istio's control plane, sends configuration to every proxy. You can read that configuration with `istioctl proxy-config`.
- **The `ServiceEntry`.** It adds a host outside the mesh to Istio's service registry, so the proxies can route to it.
- **The two-stage route through the egress gateway.** One `VirtualService` holds two rules. The rule for the gateway name `mesh` runs in every sidecar proxy and sends the request to the egress gateway. The rule for the egress gateway's `Gateway` runs in the egress gateway and sends the request on to the external host. A `DestinationRule` on the egress gateway's own Service gives the first rule an empty subset to name.

### What is in your playground

Your playground is one `kind` cluster with **Istio 1.30.5** installed with Helm. Next to `istio-base` and `istiod`, it runs an **egress gateway**:

| What | Where |
| --- | --- |
| Helm release and namespace | `istio-egress` in the namespace `istio-egress` |
| Deployment and Service | `istio-egress`, Service type `ClusterIP`, ports `80` and `443` |
| Pod label a `Gateway` selects | `istio: egress` |

The egress gateway is running and carries **no** traffic. `istiod` also has **DNS capture** switched on: the sidecar proxy answers DNS lookups for hosts that a `ServiceEntry` defines, so a pod can look up such a host by its name. The workloads live in two namespaces:

| Namespace and object | Its role |
| --- | --- |
| `starfleet` / `shuttle` | The test client. You send every test request from here, with the `curl` command. It shows `2/2`: the application container plus its sidecar proxy |
| `starfleet` / Secret `partner-client-cert` | The **client certificate** that the partner server issued for you. The last parts use it |
| `outpost` / `partner` | A **partner server** outside the mesh (no sidecar proxy). It only answers HTTPS, and only to callers that present a client certificate it trusts |

Mesh-wide access logs are on, so the shuttle's sidecar proxy **and** the egress gateway each write one line per request into their access log. There is no `ServiceEntry`, `Gateway`, `DestinationRule` or `VirtualService` yet.

> [!WARNING]
> **The first parts need outbound internet access.** They call `httpbin.org` from inside the cluster. Without internet access you see network failures, not mesh decisions. Run a plain `curl https://httpbin.org/get` on your own machine first. The partner server and the graded labs do **not** need internet access.

Start your playground now, and keep it running while you read the parts:

<!-- astrona:playground -->

### Helpers to paste first

Paste these into each new terminal. `call_httpbin` sends one plain `http://` request from the shuttle to `httpbin.org/get` and prints the address that `httpbin.org` says it was called on, plus the status code. `call_partner` does the same for the partner server. The other two print the newest line of each access log: the shuttle's sidecar proxy, and the egress gateway.

```sh
call_httpbin() { kubectl exec -n starfleet deploy/shuttle -- curl -s --max-time 15 -w "\n%{http_code}\n" http://httpbin.org/get | grep -E '"url"|^[0-9]{3}$'; }
call_partner() { kubectl exec -n starfleet deploy/shuttle -- curl -s --max-time 10 -w "%{http_code}\n" http://partner.outpost.example/; }
log_shuttle() { sleep 2; kubectl logs -n starfleet deploy/shuttle -c istio-proxy --tail=1; }
log_gate() { sleep 2; kubectl logs -n istio-egress deploy/istio-egress --tail=1; }
```

`httpbin.org` answers with the full address it was called on. The start of its `url` field tells you how the request arrived: `http://` for plain text, `https://` for TLS.

## The order of the parts

The module has five parts, a lab after the third part, a lab after the fifth part, and a summary at the end.

The first part builds four routing objects for `httpbin.org` and sends a request through the egress gateway. The request fails in a way that shows what the fifth object is for. The second part adds that object, a `DestinationRule` on the external host that turns on TLS, and shows what happens when the onward port is wrong. The third part proves which proxy holds the TLS settings, keeps them on the egress gateway with `exportTo`, and shows the most common mistake. Its lab asks you to build the five objects yourself and prove that the egress gateway, not the sidecar proxy, starts the TLS connection.

The fourth part routes requests to a stricter partner server that checks the certificates on both sides of the TLS handshake, and shows both checks fail. The fifth part gives the egress gateway a client certificate with `tls.mode: MUTUAL` and `credentialName`, and shows which namespace the `Secret` must live in. Its lab asks you to find and fix every fault in a broken mutual TLS route.

Partner APIs that ask for a client certificate are common, and the exam expects you to configure them by hand. The configuration is small, but each piece is used by a different proxy, and a mistake often still returns an answer. This module trains you to prove where TLS starts, not just to see a `200`.
