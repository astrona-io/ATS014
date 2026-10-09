# Overview: Scope Proxy Configuration With The Sidecar Resource (Playground)

> Declared in [`../config.yaml`](../config.yaml) under `metadata.docs.guide`.

Welcome, astronaut. This is your training solar system: a **playground**, not a graded mission. It starts clean, installs Istio and two planets, and then waits for you. There is no task, no `astrona submit` and no pass or fail. Explore, break things, destroy it and start again.

## What's in the box

- A single-node `kind` Kubernetes cluster. `astrona run` points `kubectl` at it.
- **Istio 1.30.5** (`istio-base` and `istiod`), installed with Helm. You need `istioctl` on your own machine.
- Access logs for every proxy, so each communications officer keeps a flight log.
- Two planets, both with sidecar injection:

| Planet | Ship | What it does |
| --- | --- | --- |
| `starfleet` | `shuttle` | your test client: send every signal from here |
| `starfleet` | `cargo` | a local service on port `9080` (`/details/0`) |
| `outpost` | `probe` v1, v2 | an echo service on port `8000` (`/get`, `/headers`) |

- **No `Sidecar` resource.** The mesh uses Istio's default outbound policy, `ALLOW_ANY`.

## Things to try

- Count the shuttle's destinations with `istioctl proxy-config cluster deploy/shuttle -n starfleet | wc -l`, then again after each `Sidecar` you apply.
- Apply a planet-wide `Sidecar` on `starfleet` with only `./*` and `istio-system/*`. Check that `probe.outpost` is gone from the shuttle's cluster list, then call it anyway and read the flight log: `PassthroughCluster`.
- Add `outboundTrafficPolicy` with `mode: REGISTRY_ONLY` to the same `Sidecar` and call the probe again: `000`, and `BlackHoleCluster` in the flight log.
- Add a selector `Sidecar` for `app: shuttle` that lists only `./*`, and compare the shuttle's cluster list with the cargo ship's.
- Leave out `istio-system/*` and see what the shuttle's proxy loses.
- Put a `Sidecar` in `istio-system` and watch the probe's star chart on `outpost` shrink.

## Start over

Remove every `Sidecar` you created:

```sh
kubectl delete sidecar --all -n starfleet
kubectl delete sidecar --all -n outpost
kubectl delete sidecar --all -n istio-system
```

## When you're done

```sh
astrona destroy ats-014-playground-010-02
```

`astrona destroy` takes the environment name, not the configuration path.
