# How A Request Moves Through The Mesh

Almost everything you do with Istio is configuration for a proxy. This module is about that proxy itself: the sidecar proxy (Envoy) that Istio adds to every pod in the mesh. You learn where it comes from, how requests reach it, where its configuration comes from, and how to ask it what configuration it holds right now.

You write no Istio objects in this module. Everything here exists as soon as a namespace is switched on for Istio. Most confusing results with Istio come from mixing up four components that sit close together. A **Service** groups pods. **kube-proxy** would send a connection to one of those pods. **`istiod`**, the control plane, builds the proxy configuration. The **sidecar proxy** in the pod that *sends* the request decides where the request goes.

## Learning objectives

After this module you can:

- Explain what sidecar injection adds to a pod, and why a namespace label alone does not change running pods.
- Tell an injected pod from an uninjected one, and bring a workload into the mesh.
- Describe how outgoing and incoming traffic reaches the proxy without the application knowing.
- Say which side of a call decides routing, and what a client without a proxy loses.
- Expand LDS, RDS, CDS and EDS, and say which one carries a given kind of configuration.
- Follow one request through the listener, route, cluster and endpoint layers, and read the output for each layer.
- Read an Envoy cluster name: direction, port, subset and host.
- Pick the right diagnostic command for a symptom, and say what each one cannot see.
- Read a response flag such as `NR`, `NC` or `UH`, and say which half of the setup to look at.

## Before you start

This module starts from zero with Istio. It expects the following knowledge, and a playground that is ready before the first hands-on step.

### What you should already know

- **Kubernetes basics.** Namespaces, Deployments, Services, pod labels, `kubectl logs` and `kubectl exec`, on a cluster where you have administrator rights.
- **No Istio yet.** You write no Istio objects in this module.

### What is in your playground

Your playground is one `kind` cluster with **Istio 1.30.5** already installed, and `istioctl` ready to use. It has two namespaces that differ in one setting.

The **`starfleet`** namespace has sidecar injection switched on, so every pod in it has a sidecar proxy. It runs the Istio Bookinfo sample app with other names:

| Workload | What it does |
| --- | --- |
| `bridge` | Web frontend (`/productpage`) on port `9080`; it calls `cargo` and `scout` |
| `cargo` | Backend that returns item details |
| `scout` v1, v2, v3 | Backend in three versions |
| `navcom` | Backend that `scout` v2 and v3 call for a rating |
| `shuttle` | Test client pod; you send test requests from here |
| `probe` v1, v2 | HTTP echo server on Service port `8000`; it returns what it receives |

The **`outpost`** namespace has sidecar injection switched **off**, on purpose. Its one pod, `drifter`, runs the same client image as `shuttle` but has no sidecar proxy.

There is no `VirtualService`, no `DestinationRule` and no policy of any kind. This module is about what the mesh does before you configure anything.

Start your playground now, and keep it running while you read the parts:

<!-- astrona:playground -->

## The order of the parts

The module has five parts, a lab after the second part, a lab after the fifth part, and a summary at the end.

The first part shows what sidecar injection adds to a pod and how to tell an injected pod from an uninjected one. The second part follows one request through the client's proxy and the server's proxy, and shows what a client without a proxy loses. Its lab asks you to bring workloads into the mesh.

The third part shows how `istiod` builds the service registry and sends configuration to every proxy over xDS. The fourth part reads that configuration layer by layer: listener, route, cluster and endpoint. The fifth part puts the diagnostic commands in a fixed order and teaches the response flags in the access log. Its lab asks you to find and fix a Service that sends every request to an empty destination.
