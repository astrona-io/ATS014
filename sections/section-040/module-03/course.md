# Outlier Detection And Endpoint Ejection

Kubernetes already has a way to take a broken pod out of a Service: the **readiness probe**. It is a health check that the kubelet, the Kubernetes agent on each node, runs against the pod. It works when the pod knows that it is broken.

It does nothing about a pod that passes its readiness probe and still answers every real request with a `503`. A wrong setting, a failed dependency or a corrupted cache can all cause this. The pod reports that it is fine, yet a share of the requests to the Service keeps failing.

**Outlier detection** is Istio's answer, and it works differently from a probe. No one sends the pod a test request. The **sidecar proxy** (Envoy) of each client, the proxy container that Istio adds to every pod, watches the responses it already receives. When one endpoint keeps failing, the proxy stops sending requests to it for a while and uses the other endpoints. This is called an **ejection**.

## Learning objectives

After this module you can:

- Explain what passive health checking is and how it differs from a readiness probe.
- Configure `trafficPolicy.outlierDetection` with `consecutive5xxErrors`, `interval`, `baseEjectionTime` and `maxEjectionPercent`.
- Choose between `consecutive5xxErrors` and `consecutiveGatewayErrors`, and state that `consecutive5xxErrors` is 5 as soon as an `outlierDetection` block exists.
- Explain why `maxEjectionPercent` at its 10% default blocks every ejection on a small Service, and prove it with the `ejections_overflow` counter.
- Predict how long an endpoint stays ejected, including after repeated ejections.
- Show an ejection with `istioctl proxy-config endpoints` and the proxy's counters, and explain why Kubernetes still lists the pod.
- Put a connection pool and outlier detection in one `DestinationRule`, and prove that both halves work.

## Before you start

This module expects some knowledge of Istio and a playground that is ready before the first hands-on step.

### What you should already know

- **How the mesh works.** A sidecar proxy runs next to every pod in the mesh, and `istiod`, Istio's control plane, sends it its configuration. You can read that configuration with `istioctl proxy-config`.
- **`DestinationRule` and `trafficPolicy`.** A `DestinationRule` sets the traffic policy for requests to one host. This module adds one more field, `outlierDetection`, inside its `trafficPolicy`.
- **Connection pools.** The `connectionPool` field of a `trafficPolicy` limits how many connections and waiting requests a client proxy may have open to a host. When the limit is reached, the proxy refuses extra requests with `503` and the response flag `UO`.

### What is in your playground

Your playground is one `kind` cluster with **Istio 1.30.5** installed with Helm. Access logs are switched on for every proxy in the mesh. Everything runs in the namespace **`starfleet`**, which has sidecar injection switched on:

| Workload | What it does |
| --- | --- |
| `probe` v1 and v2 | HTTP echo server: two healthy pods behind one Service on port `8000`. Its `/get` path answers `200` |
| `shuttle` | Test client pod; you send single requests from here. Its sidecar proxy keeps the outlier detection counters for each destination |
| `fortio` | Load generator that sends many requests at the same time; it is the second client with its own proxy |

There is **no broken pod yet and no `DestinationRule`**. The first hands-on step adds the broken pod, so you see the problem before you fix it.

Start your playground now, and keep it running while you read the parts:

<!-- astrona:playground -->

## The order of the parts

The module has four parts, a lab after the third part, a lab after the fourth part, and a summary at the end.

The first part adds a pod that is ready but fails every request, compares readiness probes with outlier detection, and applies a first rule that ejects the pod. The second part explains the timeline of an ejection and shows which status codes `consecutive5xxErrors` and `consecutiveGatewayErrors` count.

The third part covers the two safety limits, `maxEjectionPercent` and `minHealthPercent`, and shows how the 10% default blocks every ejection on a small Service. Its lab asks you to eject a failing endpoint on a Service with two endpoints.

The fourth part proves an ejection from the proxy's endpoint list and counters, shows that each proxy decides on its own and that every ejection ends, and combines outlier detection with a connection pool. Its lab asks you to build that combined rule and prove both halves.
