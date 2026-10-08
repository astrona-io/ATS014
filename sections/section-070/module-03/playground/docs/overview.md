# Overview: Add External Workloads With WorkloadEntry (Playground)

> Declared in [`../config.yaml`](../config.yaml) under `metadata.docs.guide`.

Welcome aboard, astronaut. This is a **playground**, not a lab. The environment starts clean, runs
`bootstrap/prepare.sh`, applies the starting workloads, and then waits. There is
no task, no `astrona submit`, and no pass/fail. Explore, break things,
`astrona destroy`, start over.

## What's in the box

- A single-node `kind` Kubernetes cluster with `kubectl` already pointed at it.
- **Istio 1.30.5** (`demo` profile) and `istioctl` on your PATH.
- Namespace **`vm-demo`**, injected, containing:
  - `tester` — a client pod with `curl` and a sidecar.
  - `legacy-backend` — a pod **excluded from injection** with
    `sidecar.istio.io/inject: "false"`. It stands in for a virtual machine (an old
    ship outside the fleet network): an address that answers HTTP on 8080, with no sidecar, no Service and no mesh
    membership.
  - `legacy-sa` — the ServiceAccount the stand-in runs as, so identity has
    something to point at.
- **No `WorkloadEntry`, `ServiceEntry` or `WorkloadGroup`.**

### What the stand-in cannot show you

A non-injected pod is on the pod network and does not run `istio-agent`. It
reproduces the part that matters here — a reachable address the mesh knows
nothing about — but **`WorkloadGroup` auto-registration cannot be demonstrated**,
because that needs a real VM with `istio-agent`, a provisioned token and the
mesh root certificate. Creating a `WorkloadGroup` here is a configuration
exercise, not something you can watch work.

## Things to try

- Before configuring anything, confirm the call by IP works while
  `istioctl proxy-config cluster deploy/tester -n vm-demo | grep legacy` returns
  nothing. Reachable and anonymous are different things.
- Create the `WorkloadEntry` alone and confirm the hostname still does not
  resolve. One object is not enough.
- Change `location` to `MESH_EXTERNAL` and compare. Routing still works; the
  identity does not.
- Break the label match between `workloadSelector` and the `WorkloadEntry` and
  watch the host get zero endpoints — 503 at request time, no validation error.
- Omit `serviceAccount` and reason about which policies could no longer name the
  workload.
- Add a second `WorkloadEntry` with the same labels, pointing at another address,
  and watch both appear under `istioctl proxy-config endpoints`.
- Apply a `DestinationRule` with outlier detection to `legacy.vm-demo.svc` and
  confirm it is treated like any other host.
- Write the `WorkloadGroup` as a reading exercise and compare its `template` with
  a Deployment's pod template.

## When you're done

```sh
astrona destroy ats-014-playground-070-03
```

(`astrona destroy` takes the environment name, not the configuration path.)
