# Outlier Detection And Endpoint Ejection

Astronaut, Kubernetes already has a way to take a broken spaceship (pod) out of a Service: the **readiness probe**. It is a health check the ship answers about itself, like a pilot reporting "all systems green". It works when the ship knows it is broken.

It does nothing about the ship that passes its probe and still answers every real signal with a `503`. A bad setting, a dead dependency, a corrupted cache: the ship feels fine, yet a share of your signals keeps failing.

**Outlier detection** is Istio's answer, and it works differently from a probe. Nobody asks the ship anything. The sender's communications officer (the sidecar proxy) watches the answers it is **already getting**, notices that one ship keeps failing, and stops sending to it for a while. It pulls the damaged ship out of formation and sends signals to the others.

## Learning objectives

After this module you can:

- Explain what passive health checking is and how it differs from a readiness probe.
- Configure `trafficPolicy.outlierDetection` with `consecutive5xxErrors`, `interval`, `baseEjectionTime` and `maxEjectionPercent`.
- Choose between `consecutive5xxErrors` and `consecutiveGatewayErrors`, and state that `consecutive5xxErrors` is 5 as soon as an `outlierDetection` block exists.
- Explain why `maxEjectionPercent` at its 10% default blocks every ejection on a small service, and prove it with the `ejections_overflow` counter.
- Predict how long an endpoint stays ejected, including after repeated ejections.
- Show an ejection with `istioctl proxy-config endpoints` and the proxy's counters, and explain why Kubernetes still lists the pod.
- Put a connection pool and outlier detection in one `DestinationRule`, and prove both halves work.

## Before you start

Every mission starts with a pre-flight check, astronaut. Make sure you have the knowledge this module expects, know what is in your playground, and have four helpers ready in your terminal.

### What you should already know

- **How the mesh works.** A proxy (the communications officer) sits beside every pod, and `istiod` (mission control) sends it orders. You can read those orders with `istioctl proxy-config`.
- **`DestinationRule` and `trafficPolicy`.** This module adds one more key, `outlierDetection`, inside the same `trafficPolicy`.
- **A connection pool.** The last part combines `outlierDetection` with `connectionPool`, the shields that refuse signals with `503 UO` when too many are open at once.

### What is in your playground

Your playground is a training solar system: one `kind` cluster with **Istio 1.30.5** installed with Helm, and flight logs switched on for every ship. Everything lives on one planet, the namespace **`starfleet`**:

| Ship | What it does |
| --- | --- |
| `probe` v1 and v2 | The **echo probe**: two healthy pods behind one Service on port `8000`. Its `/get` path answers `200` |
| `shuttle` | **Your shuttle**: the client you send single signals from. Its communications officer is set up to keep the outlier-detection counters you read later |
| `fortio` | The **load generator**: it fires many signals at the same time. The last part uses it |

There is **no broken pod yet and no `DestinationRule`**. The first part adds the broken pod, so you see the problem before you fix it.

Launch your playground now, and keep it running next to you while you read the parts:

<!-- astrona:playground -->

### Four helpers to paste first

Paste these into each new terminal. Each comment says what the helper does:

```sh
# 15 single signals from the shuttle to the probe, counted by status code
count_status() { for i in $(seq 1 15); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" http://probe:8000/get
done | sort | uniq -c; }
# the probe's endpoints as the shuttle's proxy sees them, with the OUTLIER CHECK column
show_endpoints() { istioctl proxy-config endpoints deploy/shuttle -n starfleet --cluster "outbound|8000||probe.starfleet.svc.cluster.local"; }
# the shuttle proxy's outlier-detection counters for the probe
ejection_stats() { kubectl exec -n starfleet deploy/shuttle -c istio-proxy -- \
  pilot-agent request GET stats 2>/dev/null | grep -E 'probe.starfleet.*outlier_detection.ejections_(active|total|enforced_consecutive_5xx):'; }
# 30 signals to the probe over N parallel connections, from fortio
load_test() { kubectl exec -n starfleet deploy/fortio -c fortio -- \
  fortio load -c "$1" -qps 0 -n 30 -loglevel Warning http://probe:8000/get 2>&1 | grep -E "^Code"; }
```

Check that the playground is healthy before you break anything:

```sh
count_status
```

```text
  15 200
```

## Why this matters

A readiness probe only catches a ship that knows it is broken. Real outages are often the other kind: a pod that looks fine and fails real work. Outlier detection catches those from the sender's side, using nothing but the answers it already gets.

It is also the base for other resilience features. Istio's locality failover, for example, has no health checker of its own: it treats an endpoint as unhealthy only when outlier detection has ejected it. Without `outlierDetection`, nothing is ever marked unhealthy.
