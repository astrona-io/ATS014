# Apply And Remove Traffic Rules Safely

Astronaut, writing a correct flight plan is half the job. The other half is changing a live fleet without breaking it on the way. Istio's objects point at each other: a `VirtualService` points at subsets in a `DestinationRule`, and at a `Gateway`. A route can point at an outside host from a `ServiceEntry`. If a pointer arrives before the thing it points at, signals fail, even though every object is correct.

Mission control (`istiod`) does not reach every ship at the same moment. For a short time, some ships fly the new flight plan and some still fly the old one. This module teaches the order of changes that keeps every ship flying safely through that gap.

## Learning objectives

After this module you can:

- Name the order to create `ServiceEntry`, `DestinationRule`, `Gateway` and `VirtualService`, and the reverse order to remove them.
- Explain "make before break", and reproduce the `503 NC` that the wrong order causes.
- Check that the sender's proxy has a new subset with `istioctl proxy-config clusters` before you test.
- Explain why two files with the same `metadata.name` describe one object, and why to avoid two objects for one host.
- State Istio's defaults for HTTP timeout, retries, load balancing, unknown outside hosts and circuit breaking, and prove two of them.

## Before you start

Every mission starts with a pre-flight check, astronaut. Make sure you have the knowledge this module expects, and know what is waiting in your playground.

### What you should already know

- **Subsets and routes.** A `DestinationRule` names ship classes (subsets) over pod labels, and a `VirtualService` route sends signals to one of them.
- **The two `503` flags.** `NC` means the route names a subset that has no cluster. `UH` means the cluster has no healthy pods.
- **Kubernetes basics.** Namespaces, Deployments, Services, pod labels and `kubectl exec`.

The other objects named here (`Gateway`, `ServiceEntry`, `Sidecar`) only need to be names for now: what matters is what they point at.

### What is in your playground

Your playground is a small training solar system: one `kind` cluster with **Istio 1.30.5** installed with Helm, and flight logs (access logs) switched on for every proxy. Everything lives on one planet, the namespace **`starfleet`**:

| Ship | Its role in the fleet |
| --- | --- |
| `bridge`, `cargo`, `navcom` | The flagship, the supply ship and the navigation computer of the Starfleet |
| `scout` v1, v2, v3 | Three ship classes of the same scout. v1 reports no stars, v2 black stars, v3 red stars |
| `shuttle` | Your test client. You send every test signal from here |
| `probe` v1, v2 | The echo probe. It answers on paths like `/delay/3` and `/status/503`, which makes defaults easy to see |

There is **no** `DestinationRule` and **no** `VirtualService` yet. You apply them in the order this module teaches.

One name did not change: the path inside each signal. The ships run the official Bookinfo images, which answer on fixed paths, so a signal to the scout is `http://scout:9080/reviews/0`.

Launch your playground now, and keep it running next to you while you read the parts:

<!-- astrona:playground -->

## Why this matters

Every change you make to a live mesh is a moment where some proxies have the new orders and some do not. Most of the time the gap is too short to notice. Under real traffic, the wrong order turns that short gap into a burst of `503` errors on every change. The order in this module is the habit that keeps your changes invisible to the ships in flight.
