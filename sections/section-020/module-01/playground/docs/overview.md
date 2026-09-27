# Overview: Shift Traffic With Weighted Routing (Playground)

> Declared in [`../config.yaml`](../config.yaml) under `metadata.docs.guide`.

This is a **playground**, not a lab. The environment starts clean, runs
`bootstrap/prepare.sh`, applies the starting workloads, and then waits. There is
no task, no `astrona submit`, and no pass/fail. Explore, break things,
`astrona destroy`, start over.

## What's in the box

- A single-node `kind` Kubernetes cluster with `kubectl` already pointed at it.
- **Istio 1.30.5** (`demo` profile) and `istioctl` on your PATH.
- Namespace **`shifting-demo`**, injected, containing:
  - `notification-service-v1` (answers `["EMAIL"]`) and
    `notification-service-v2` (answers `["EMAIL","SMS"]`) — the different
    response bodies are how you count a split.
  - `notification-service` — one Service in front of both.
  - `tester` — a client pod with `curl`.
- **No `VirtualService` and no `DestinationRule`**, so all traffic is still an
  unweighted kube-proxy coin toss.

## Things to try

- Apply an 80/20 split and count 10 requests, then 100, then 1000. Watch the
  measured ratio settle — that is why small samples mislead.
- Try weights that sum to 90 and read the admission error instead of guessing.
- Omit `weight` on a two-destination route and see what the API server says.
- Scale `notification-service-v1` to 10 replicas at a 50/50 split and confirm
  the share does not move. Then scale `v2` to 0 and see what 50% of traffic to
  an empty subset looks like.
- Script a five-step rollout, 0 → 20 → 40 → 60 → 80 → 100, with a `sleep 5`
  between steps, and measure at each step.
- Put a header match rule *above* the weighted rule and work out from the counts
  how much traffic never reaches the weights at all.
- Compare `istioctl proxy-config routes deploy/tester -n shifting-demo -o json`
  before and after a weight change.

## When you're done

```sh
astrona destroy ats-014-playground-020-01
```

(`astrona destroy` takes the environment name, not the config path.)
