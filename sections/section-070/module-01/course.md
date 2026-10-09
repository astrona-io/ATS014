# Control External Access With ServiceEntry

Astronaut, until now every signal you steered flew between ships in your own solar system. Real applications also signal *out*: a payment API, an object store, a partner's endpoint, a package registry. These are planets in other solar systems. Traffic that leaves the cluster like this is called **egress**.

Istio knows nothing about those planets. They are not Kubernetes Services, so they are not in Istio's **service registry**: the star chart of every planet and beacon that mission control (`istiod`) knows about. A host that is not on the chart cannot be routed, timed out or reported on. And by default, it is not stopped either.

Two tools change that:

> A **`ServiceEntry`** adds a planet from another solar system to the star chart. **`REGISTRY_ONLY`** turns the default around: ships may signal only charted planets, and everything else falls into a black hole.

Once a host is on the chart, it stops being special. The `VirtualService` (the flight plan) and the `DestinationRule` (the docking instructions) work on it exactly as they work on a Service inside the cluster. So a `ServiceEntry` is two things at once: a permission to leave, and a way to put Istio's features on somebody else's API.

## Learning objectives

After this module you can:

- Explain `meshConfig.outboundTrafficPolicy.mode` and the difference between `ALLOW_ANY` and `REGISTRY_ONLY`.
- Lock down one namespace with `outboundTrafficPolicy` on a `Sidecar` resource.
- Recognise the answer a blocked destination produces, and tell it apart from a network failure.
- Read `PassthroughCluster`, `BlackHoleCluster` and `outbound|443||<host>` in the flight log, and say which path a signal took.
- Write a `ServiceEntry` for an external host, with the right `location` and `resolution`.
- Explain why the declared `protocol` decides whether HTTP features are available.
- Apply a `VirtualService` timeout and a `DestinationRule` connection pool to an external host.
- Limit a `ServiceEntry` with `exportTo`, and find the cause when a `Sidecar` hides one.

## Before you start

Every mission starts with a pre-flight check, astronaut. Check what you should already know, see what waits in your playground, and paste one helper into your terminal.

### What you should already know

- **How the mesh works.** A proxy (the communications officer) sits beside every pod, and `istiod` (mission control) sends it orders. You can read those orders with `istioctl proxy-config`.
- **The flight plan and the docking instructions.** A `VirtualService` with a `timeout`, and a `DestinationRule` with a `connectionPool`.
- **The `Sidecar` resource.** It gives the proxies in one namespace a smaller star chart with `egress.hosts`.

### What is in your playground

Your playground is a small training solar system: one `kind` cluster with **Istio 1.30.5** installed with Helm (`istio-base` and `istiod` only, no gateways). The mesh is at its default, `ALLOW_ANY`. Everything you need is on one planet, the namespace **`starfleet`**:

| Ship | Its role |
| --- | --- |
| `shuttle` | **Your shuttle**. You send every test signal from here, with the `curl` command |
| `probe` v1, v2 | An **echo probe** inside the cluster, on port `8000`. You use it to compare a signal that stays home with one that leaves |

Every pod shows `2/2`: the app plus its communications officer (the `istio-proxy` sidecar). Mesh-wide access logs are on, so every proxy writes one line per signal into its flight log. There is **no** `ServiceEntry` and **no** `Sidecar` yet: the star chart only knows your own solar system.

> [!WARNING]
> **This module needs outbound internet access.** The commands call real hosts on the internet: `httpbin.org`, `de.wikipedia.org`, `en.wikipedia.org` and `www.google.com`. Without internet access you see network failures, not mesh decisions. Run a plain `curl https://httpbin.org/get` on your own machine first. The graded missions do **not** need internet access.

Launch your playground now, and keep it running next to you while you read the parts:

<!-- astrona:playground -->

### One helper to paste first

Paste this into each new terminal. It sends one signal from the shuttle and prints the status code, the time, and the exit code of `curl`:

```sh
call_external() { kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" --max-time 10 "$@"; echo "  exit=$?"; }
```

Use it like this: `call_external https://httpbin.org/get`. A result of `000` with exit `35` or `56` means the connection was cut before any HTTP answer came back.

## Why this matters

Most applications depend on something outside the cluster. Under the default, that traffic is invisible to the mesh: no routing, no timeouts, no record of where it went. A `ServiceEntry` makes it visible and controllable, and `REGISTRY_ONLY` makes sure nothing leaves without one.

This module also trains a diagnostic habit. A refusal looks almost exactly like a network failure. The flight log tells them apart, and the shuttle's own proxy shows which planets are on its star chart.
