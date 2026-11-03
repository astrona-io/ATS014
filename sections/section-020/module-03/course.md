# Shift TCP Connections With Weights

Weighted routing for HTTP sends a share of requests to a new version of a service. The sidecar proxy reads each request, so it can pick a destination for every request on its own. Not every service speaks a protocol that the proxy reads. When the proxy treats a port as plain TCP (Transmission Control Protocol), it sees a stream of bytes and no requests. Istio can still split that traffic by weight, but the unit changes: the weight applies to each **connection**, not to each request.

That change has real consequences. A client that opens one connection and keeps it open sends everything to one pod, whatever the weights say. A rollout of a TCP service needs a different way of counting, and a different way of checking that the split is real. This module teaches both, on the same `probe` pods you can already read with HTTP.

## Learning objectives

After this module you can:

- Create a second Service for existing pods whose port name makes Istio treat it as plain TCP.
- Write a `VirtualService` with a `tcp` route, a `match` on the port and weighted destinations, and the `DestinationRule` that defines the subsets.
- Explain why a weight applies once per connection, and why a client that reuses one connection stays on one pod.
- Sample a TCP split honestly, with a new connection for every sample, and judge how close a count of connections must be to the weights.
- Read the weighted clusters of a TCP route from the proxy of the client, and tell a TCP route from an HTTP route in the proxy configuration.
- Roll a TCP service forward from 100/0 to 90/10, 50/50 and 0/100 with `kubectl patch`, and roll it back.
- Diagnose a `tcp` route that never applies because the Service port is named `http`.

## Before you start

This module expects some knowledge of Istio routing, a running playground and two helper scripts.

### What you should already know

- **How the mesh works.** Istio adds a sidecar proxy (Envoy) to every pod in the mesh, and all traffic of the pod passes through it. `istiod`, the control plane, sends each proxy its configuration. You can read that configuration with `istioctl proxy-config`.
- **Subsets and weights.** A `DestinationRule` defines subsets: named groups of a Service's pods, selected by labels such as `version: v2`. A `VirtualService` sets how traffic to a host is routed, and can give each destination a `weight`.
- **Kubernetes basics.** Namespaces, Deployments, Services, pod labels, `kubectl exec` and `kubectl patch`.

### What is in your playground

Your playground is one `kind` cluster with **Istio 1.30.5** already installed. Access logs are switched on for every proxy. Everything runs in the namespace **`starfleet`**:

| Workload | What it does |
| --- | --- |
| `probe` v1, v2 | HTTP echo server in two versions behind the Service `probe` on port `8000`. Its `/hostname` path returns the name of the pod that handled the request |
| `shuttle` | Test client pod in the mesh. You send every test request from here |

Every pod shows `2/2`: the application container plus the `istio-proxy` sidecar container. There is **no** `DestinationRule` and **no** `VirtualService` yet, and no Service for TCP. You create them in this module.

Start your playground now, and keep it running while you read the parts:

<!-- astrona:playground -->

### Two helpers

Two scripts ship with the playground. Both send requests from `shuttle`, and both count which version answered. They take the number of samples first (20 if you give none), and the target second (`probe-tcp:8000` if you give none). Run them with `astrona res run`, and put the arguments after `--`.

- `count-connections.sh` opens a **new connection for every sample**, because it starts one `curl` process per sample.
- `count-reused.sh` sends all samples over **one connection**, because it gives one `curl` process all the URLs.

For example, `astrona res run count-connections.sh -- 100` samples 100 connections.

## The order of the parts

The module has three parts, a lab after the second part, a lab after the third part, and a summary at the end.

The first part makes a second Service whose port is named `tcp`, and writes a `VirtualService` with a weighted `tcp` route and the `DestinationRule` for its subsets. The second part shows that the weight is drawn once per connection, that one reused connection stays on one pod, and how many connections a count needs. Its lab asks you to build an 80/20 split between two subsets, which the grader proves with many fresh connections.

The third part rolls the service forward in steps and back again with `kubectl patch`, and then breaks the setup on purpose: it renames the port to `http` and shows what the proxy does with a `tcp` route on an HTTP port. Its lab asks you to find and fix a split that never happens.
