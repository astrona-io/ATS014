# Overview: Route External Traffic Through An Egress Gateway (Playground)

> Declared in [`../config.yaml`](../config.yaml) under `metadata.docs.guide`.

This is a **playground**, not a lab. The environment starts clean, runs
`bootstrap/prepare.sh`, applies the starting workloads, and then waits. There is
no task, no `astrona submit`, and no pass/fail. Explore, break things,
`astrona destroy`, start over.

## What's in the box

- A single-node `kind` Kubernetes cluster with `kubectl` already pointed at it.
- **Istio 1.30.5** installed with the `demo` profile, which includes
  **`istio-egressgateway`** in `istio-system` — running, and carrying no traffic.
- Namespace **`egwgw-demo`**, injected, with a `tester` client pod.
- The mesh at its `ALLOW_ANY` default.
- **No `ServiceEntry`, `Gateway` or `VirtualService`.**

### Outbound internet

The commands reach `httpbin.org`. Without outbound internet access you will see
network errors rather than mesh behaviour.

## Things to try

- Before configuring anything, call an external host and then
  `kubectl -n istio-system logs deploy/istio-egressgateway | grep -c httpbin.org`.
  Zero. A running egress gateway proves nothing about where traffic goes.
- Put an *internal* hostname in the `Gateway`'s `servers[].hosts` and watch the
  gateway reject everything you send it.
- Swap the two `match.gateways` values and observe the failure. That mistake is
  worth making once deliberately.
- Drop `mesh` from the top-level `gateways` list and confirm no traffic is
  diverted at all — the sidecar-side rule was never programmed into sidecars.
- Delete the `ServiceEntry` while leaving everything else and see what breaks.
- Add `sourceLabels: {app: tester}` to the mesh-side match, then run a second
  client pod with a different label and confirm it takes the direct path
  instead. `sourceLabels` narrows the route, not the permission.
- Switch the mesh to `REGISTRY_ONLY` and re-read that last point.
- Compare `istioctl proxy-config routes deploy/tester -n egwgw-demo --name 80`
  before and after, and find the `|httpbin|` subset in the cluster name.
- Scale `istio-egressgateway` to 0 and watch external calls fail. The gateway is
  on the critical path now.

## When you're done

```sh
astrona destroy ats-014-playground-080-01
```

(`astrona destroy` takes the environment name, not the config path.)
