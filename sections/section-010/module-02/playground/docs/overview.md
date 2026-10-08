# Overview: Scope Proxy Configuration With The Sidecar Resource (Playground)

> Declared in [`../config.yaml`](../config.yaml) under `metadata.docs.guide`.

This is a **playground**, not a lab: your training solar system. The environment starts clean, runs
`bootstrap/prepare.sh`, applies the starting workloads, and then waits. There is
no task, no `astrona submit`, and no pass/fail. Explore, break things,
`astrona destroy`, start over.

## What's in the box

- A single-node `kind` Kubernetes cluster with `kubectl` already pointed at it.
- **Istio 1.30.5**, installed with the `demo` profile, plus `istioctl` on your
  PATH.
- Two injected namespaces (two planets), because scoping needs somewhere to cut off:
  - **`sidecar-demo`** — a `tester` client pod with `curl`.
  - **`sidecar-other`** — an `httpbin` Deployment and Service on port 8000.
- **No `Sidecar` resource.** Every proxy still carries the full star chart (the
  service registry), which is the starting point the module measures against.

## Things to try

- Record `istioctl proxy-config cluster deploy/tester -n sidecar-demo | wc -l`
  before you change anything, then after each edit below. The number is the
  whole experiment.
- Apply a namespace-wide `Sidecar` with `./*` and `istio-system/*`, then call
  `httpbin.sidecar-other:8000` and watch it fail — configuration removal is a
  reachability change.
- Deliberately omit `istio-system/*` and look for what degrades. Some things
  keep working, which is exactly why this mistake survives review.
- Add a `workloadSelector` that matches nothing and confirm the namespace
  default stops applying to `tester`.
- Set `outboundTrafficPolicy.mode: REGISTRY_ONLY` inside the `Sidecar` and call
  a host outside the registry.
- Patch the `egress.hosts` list to add `sidecar-other/*` back and time how long
  the running proxy takes to pick it up. No pod restart is involved.

## When you're done

```sh
astrona destroy ats-014-playground-010-02
```

(`astrona destroy` takes the environment name, not the configuration path.)
