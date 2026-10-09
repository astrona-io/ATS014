# Scope Proxy Configuration With The Sidecar Resource

Astronaut, this module is about the star chart each ship carries. Ask a communications officer (the sidecar proxy) in a fresh mesh which beacons it knows about, and the answer is: all of them. Every Service on every planet, whether or not the ship beside it will ever send a signal there.

That default means routing works without you declaring anything. But it has a cost that grows with the size of the solar system, not with your app. The `Sidecar` resource is how you cut it down: it gives a ship a smaller star chart, with only the planets it needs.

> Every communications officer knows every beacon by default. The `Sidecar` resource is how you cut that down.

The object itself is small: four fields. The interesting parts are what it changes inside the proxy, the little host language it uses, which `Sidecar` wins when several could apply, and what it can never do for you.

## How this module is organised

1. **[Every Ship Carries The Whole Star Chart](./course-01-every-ship-carries-the-whole-star-chart.md)**: what mission control gives every proxy by default, how it gets there, and why the cost grows with the mesh.
2. **[Give A Ship A Smaller Star Chart](./course-02-give-a-ship-a-smaller-star-chart.md)**: the four fields, the `<namespace>/<host>` language, and what really happens to a signal for a planet that is off the chart.
3. **[Which Star Chart A Ship Uses](./course-03-which-star-chart-a-ship-uses.md)**: selector, planet and mesh-wide defaults, and why the winner replaces the rest.
4. **[A Star Chart Is Not A Shield](./course-04-a-star-chart-is-not-a-shield.md)**: what a `Sidecar` cannot stop, which object does, and the order to check things in when a host goes missing.

Parts 2 and 3 each end with a graded mission. The wrap-up recaps the module and cleans up your playground.

## Learning objectives

After this module you can:

- Describe what a proxy is given when no `Sidecar` exists, and explain why that scales badly.
- Explain how a configuration change reaches a running proxy, and why no pod restart is involved.
- Write a planet-wide `Sidecar` that limits `egress.hosts`, using the `<namespace>/<host>` language correctly.
- Explain what `./*`, `*/*` and `istio-system/*` each select, and why the last is near-mandatory.
- Predict what happens to a signal for a host that is off the chart, under `ALLOW_ANY` and under `REGISTRY_ONLY`.
- Predict which `Sidecar` applies to a given ship, including selector precedence and the root default.
- Prove a scoping change took effect without sending any signal.
- Explain why a `Sidecar` is not a security boundary, and name what to combine it with.

## Before you start

Every mission starts with a pre-flight check, astronaut. Make sure you have the knowledge this module expects and know what is waiting in your playground.

### What you should already know

- **How the mesh works.** A proxy (the communications officer) sits beside every pod, and `istiod` (mission control) sends it orders. You can read those orders with `istioctl proxy-config`.
- **Kubernetes basics.** Namespaces, Deployments, Services, pod labels and `kubectl exec`.

### What is in your playground

Your playground is a small training solar system: one `kind` cluster with **Istio 1.30.5** already installed, and two planets (namespaces), both with sidecar injection:

| Planet | Ship | What it does |
| --- | --- | --- |
| `starfleet` | `shuttle` | your shuttle: every test signal is sent from here |
| `starfleet` | `cargo` | the supply ship, a local service on port `9080` |
| `outpost` | `probe` v1, v2 | the echo probe on another planet, on port `8000` |

Every pod shows `2/2`: the app plus its communications officer. There is **no** `Sidecar` resource yet. The mesh uses Istio's default outbound policy, `ALLOW_ANY`.

Launch your playground now, and keep it running next to you while you read the parts:

<!-- astrona:playground -->

## Why this matters

Everything else in Istio traffic management adds configuration to proxies. The `Sidecar` resource is the one that takes it away. In a big mesh with no scoping, every proxy carries every Service and gets new orders whenever anything changes anywhere.

It is also a quiet cause of failures. A perfectly correct host can be missing from one ship, simply because a `Sidecar` on that ship's planet never listed it. After this module, you can tell that apart from a host that was never defined.
