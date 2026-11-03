# TLS Settings In A DestinationRule

When a pod calls another pod in the mesh, the **sidecar proxy** of the calling pod opens the connection. The sidecar proxy is the Envoy proxy container that Istio adds to each pod; all traffic of the pod passes through it. That proxy decides whether the connection uses Transport Layer Security (TLS), the protocol that encrypts a connection and lets the two sides check each other's certificates. This module is about that decision and the field that controls it: `trafficPolicy.tls` in a `DestinationRule`, the Istio object that holds policies for traffic to one host.

The decision matters because the receiving side has its own rule. A `PeerAuthentication` is an Istio object that tells the sidecar proxy of a workload which connections it accepts. With mode `STRICT` it accepts only mutual TLS (mTLS) connections, where both sides present a certificate. If the `DestinationRule` of the caller and the `PeerAuthentication` of the destination disagree, calls fail. This module teaches you to write the client side so it matches, to read what the proxy really does, and to set it per subset and per port.

## Learning objectives

After this module you can:

- Name the four client TLS modes (`DISABLE`, `SIMPLE`, `MUTUAL`, `ISTIO_MUTUAL`) and say what each one does to the connection the client proxy opens.
- Explain automatic mTLS: what the proxy does when a `DestinationRule` has no `tls` block.
- Read the TLS setting of a cluster from `istioctl proxy-config cluster -o json` and from the access log.
- Say what a `PeerAuthentication` with mode `STRICT` does, and why a `DestinationRule` with `tls.mode: DISABLE` makes calls to that workload fail.
- Describe the symptom of that mismatch, and fix it with `ISTIO_MUTUAL` or by removing the `tls` block.
- Explain why a client with no sidecar proxy cannot reach a `STRICT` workload, and why no `DestinationRule` can fix that.
- Override `tls` for one subset or one port, and say which other settings a subset keeps from the host and which it loses.

## What you should know first

You should know that `istiod`, Istio's control plane, sends configuration to every sidecar proxy, and that `istioctl proxy-config` prints the configuration a proxy holds. You should know that a `DestinationRule` can define subsets: named groups of a host's pods, chosen by pod labels. A `VirtualService`, the Istio object that holds routing rules, sends requests to a subset. You do not need to know how Istio issues certificates.

## Your playground

The playground is one `kind` cluster with Istio 1.30.5, installed with Helm, and access logs switched on for every proxy. The namespace `starfleet` has sidecar injection on. It runs the `probe` Service on port `8000`, with three `probe-v1` pods and one `probe-v2` pod. Its path `/hostname` returns the name of the pod that served the request. The `shuttle` pod is the client; you send test requests from it.

The namespace `outpost` has sidecar injection off. It runs the `drifter` pod, a client with no sidecar proxy. No `PeerAuthentication` and no `DestinationRule` exists yet. Start the playground now and keep it running while you read the parts:

<!-- astrona:playground -->

## The order of the parts

The module has three parts. The first part explains the four client TLS modes and automatic mTLS, and shows how to read the TLS setting of a connection from the proxy. The second part adds a `PeerAuthentication` with mode `STRICT` to the destination, shows how a `DestinationRule` with `DISABLE` breaks the calls, and fixes it. It also shows why a client with no sidecar proxy cannot reach the destination.

The third part overrides `tls` for one subset and for one port, and shows exactly what a subset keeps from the host and what it replaces. Two labs follow it: you build a `DestinationRule` for a `STRICT` destination, and you fix a broken one. A short summary closes the module.
