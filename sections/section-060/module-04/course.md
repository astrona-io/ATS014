# Secure An Istio Ingress Gateway With TLS

Clients expect HTTPS for anything that leaves their machine. HTTPS is HTTP inside a TLS (Transport Layer Security) connection: TLS encrypts the traffic and lets the client check the server's certificate. When a request comes in from outside the cluster, the ingress gateway, an Envoy proxy at the edge of the mesh, is the first component that can answer it. So the gateway is the natural place to switch TLS on.

Istio's `Gateway` object has a `tls` block for this. It has three modes, a field that names the certificate, and a switch that redirects plain HTTP to HTTPS. This module teaches that block, field by field, and how to prove it works with real requests and with `istioctl`.

## Learning objectives

After this module you can:

- Terminate HTTPS on an ingress gateway with `tls.mode: SIMPLE` and `credentialName`, using a secret of type `kubernetes.io/tls` in the gateway's namespace.
- Prove which certificate a gateway serves, with `curl --resolve`, `openssl s_client` and `istioctl proxy-config secret`.
- Redirect HTTP to HTTPS with `httpsRedirect: true` on the port 80 server.
- Serve several hosts on port 443, each with its own `credentialName`, and explain how SNI (Server Name Indication) picks the certificate.
- Recognise a secret that is missing, in the wrong namespace or named differently from `credentialName`.
- Require client certificates with `tls.mode: MUTUAL`, and build the secret with `tls.crt`, `tls.key` and `ca.crt`.
- Pass encrypted traffic through with `tls.mode: PASSTHROUGH`, and route it with a `tls:` match on `sniHosts` in a `VirtualService`.

## Before you start

This module expects some knowledge, and it uses a playground with the example workloads already running.

### What you should already know

- **How a `Gateway` and a `VirtualService` work together.** A `Gateway` opens a port on an ingress gateway pod, found by a pod label `selector`. A `VirtualService` with a `gateways:` field routes the requests that come in on that port.
- **What an ingress gateway is.** It is the Deployment `istio-ingressgateway` in the namespace `istio-system`. `istiod`, Istio's control plane, sends it configuration, and you can read that configuration with `istioctl proxy-config`.
- **Kubernetes basics.** Namespaces, Secrets, Services and `kubectl apply`.

### What is in your playground

Your playground is one `kind` cluster with **Istio 1.30.5** and its ingress gateway installed. The example workloads run in the namespace **`starfleet`**:

| Workload | What it is |
| --- | --- |
| `bridge` | Web frontend. Its page, `/productpage` on port `9080`, is what you expose |
| `probe` v1, v2 | HTTP echo server on port `8000`. It answers any path under `/anything`, and `/hostname` returns the name of the pod that answered |
| `archive` | An nginx server that terminates TLS itself on port `8443`, behind the Service `archive` on port `443`. It has no sidecar proxy and its own certificate for `archive.starfleet.example.com`. It answers every request with `{"service":"archive"}` |
| `cargo`, `scout` v1/v2/v3, `navcom` | Backends that `bridge` calls to build its page |
| `shuttle` | Test client pod inside the mesh |

There is **no** `Gateway`, **no** `VirtualService` and **no** gateway certificate yet. You create them in this module.

The playground forwards two local ports to the ingress gateway:

| On your machine | Gateway port |
| --- | --- |
| `http://localhost:8080` | `80` (plain HTTP) |
| `https://localhost:8443` | `443` (HTTPS) |

Start your playground now, and keep it running while you read the parts:

<!-- astrona:playground -->

### One variable to set first

Paste this into each new terminal. Commands that send plain HTTP requests use it:

```sh
GATEWAY_URL=localhost:8080
```

The playground also has a helper script, `https-status.sh`. It sends one HTTPS request through the gateway for a path and a host name, and prints only the status code. Run it with `astrona res run https-status.sh -- /productpage`. This module also shows the full `curl` command, so you learn what the helper does.

## How this module is organised

The module has three parts. The first part terminates HTTPS on the gateway with one certificate and shows how to prove it. The second part redirects HTTP to HTTPS, serves several hosts with their own certificates, and shows what a wrong secret looks like; a build lab follows it. The third part requires client certificates with `MUTUAL` and passes encrypted traffic through with `PASSTHROUGH`; a troubleshooting lab follows it. A summary closes the module.
