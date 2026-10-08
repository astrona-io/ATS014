# Overview: Shift Traffic With Weighted Routing (Playground)

> Declared in [`../config.yaml`](../config.yaml) under `metadata.docs.guide`.

Welcome aboard, astronaut. This is a **playground**, not a lab: a training
solar system in the simulator. It starts, installs Istio and the
Starfleet, and then waits for you. There is no task, no `astrona submit`
and no pass or fail. Try things, break things, `astrona destroy`, start over.

## What's in the box

- A single-node `kind` Kubernetes cluster. `astrona run` points `kubectl` at it
  (context `kind-astro-ats-014-playground-020-01`).
- **Istio 1.30.5**, installed with Helm: `istio-base` (the CRDs) and `istiod`.
  There is no ingress or egress gateway. You need `istioctl` on your own
  machine for the `istioctl` commands.
- Namespace **`starfleet`**, labelled `istio-injection=enabled`, with:
  - **The Starfleet** (the Istio docs' Bookinfo sample, renamed): `bridge`,
    the flagship page; `cargo`, the supply ship; `navcom`, the navigation
    computer; and `scout` in three versions (ship classes). `scout-v1` shows no stars, `v2` black stars, `v3` red stars.
  - `shuttle`, a client pod inside the mesh. You send test requests from it.
  - `probe` v1 and v2 on port `8000`, a test service you can use freely.
- Access logs are on for the whole mesh, so each sidecar writes one line per
  request.
- The **`scout` DestinationRule** is already applied, with subsets `v1`,
  `v2` and `v3`. A subset is a ship class: the same `scout` model, built
  three ways.
- **No VirtualService.** Writing the weighted flight plan is the point of the
  module, so for now the Kubernetes Service spreads traffic over all three
  versions.
- The bridge page at <http://127.0.0.1:9080/productpage>. Refresh it during a
  split and watch the stars change from one request to the next.

Every pod shows `2/2`: the app plus its `istio-proxy` sidecar.

## The helper used in this module

Paste this once in each new terminal. It sends N requests (20 if you give no
number) to `scout` and counts which version answered. The scout answers on the path `/reviews/0`: the path is built into the app, so it keeps its original name. The answer contains
`"podname": "scout-vX-..."`, which is how it tells the versions apart. Extra
`curl` options go after N:

```sh
count_versions() { n=${1:-20}; [ $# -gt 0 ] && shift; for i in $(seq 1 $n); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s "$@" http://scout:9080/reviews/0 | grep -o 'scout-v[0-9]'
done | sort | uniq -c; }
# count_versions 40                        40 requests
# count_versions 10 -H "end-user: jason"   10 requests as jason
```

## Ready-made YAML

The folder [`../examples/`](../examples/) holds the files the module uses, in
the order you apply them. If you cloned the repository, apply them from there.
Otherwise the course parts show each one, ready to write to a file.

| File | What it does |
| --- | --- |
| `01-virtualservice-scout-v1-80-v3-20.yaml` | Canary step 1: 80% v1, 20% v3 |
| `02-virtualservice-scout-v1-50-v3-50.yaml` | Canary step 2: 50/50 |
| `03-virtualservice-scout-v3-100.yaml` | Canary step 3: all traffic on v3 |
| `04-virtualservice-scout-v1-rollback.yaml` | Rollback: all traffic back on v1 |
| `cases/c1-…-weights-not-100.yaml` | Weights 50 + 30 that do not add up to 100 |
| `cases/c2-…-three-way-split.yaml` | 50% v1, 25% v2, 25% v3 |
| `cases/c3-…-weight-zero.yaml` | v3 in the route with weight 0 |
| `cases/c4-…-header-plus-canary.yaml` | jason always on v3, everyone else 90/10 |

## Things to try

- Count 20 requests before you write anything. All three versions answer,
  because the Kubernetes Service picks pods, not versions.
- Apply the 80/20 canary and count 20 requests, then 100. See how much the
  small sample wobbles.
- Walk the rollout forward (80/20, 50/50, 100) and then roll it back with one
  apply. No pod restarts at any step.
- Scale `scout-v1` to 4 replicas at a 50/50 split. The share stays 50/50.
- Apply the weights that add up to 80 and work out the share each version
  gets.
- Put jason on v3 above a 90/10 split, and check that jason never enters the
  split.

## Exam-style practice

Try the drill in [`practice.md`](practice.md). It has a checked solution.

## Start over without a new cluster

```sh
kubectl delete virtualservice --all -n starfleet
```

The `scout` DestinationRule stays, so you are back at the starting state.

## When you're done

```sh
astrona destroy ats-014-playground-020-01
```

`astrona destroy` takes the environment name, not the configuration path.
