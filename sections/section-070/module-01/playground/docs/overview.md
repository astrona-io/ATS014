# Overview: Control External Access With ServiceEntry (Playground)

> Declared in [`../config.yaml`](../config.yaml) under `metadata.docs.guide`.

This is a **playground**, not a lab. The environment starts clean, runs
`bootstrap/prepare.sh`, applies the starting workloads, and then waits. There is
no task, no `astrona submit`, and no pass/fail. Explore, break things,
`astrona destroy`, start over.

## What's in the box

- A single-node `kind` Kubernetes cluster with `kubectl` already pointed at it.
- **Istio 1.30.5** (`demo` profile) and `istioctl` on your PATH. The mesh is at
  its **`ALLOW_ANY`** default — switching it to `REGISTRY_ONLY` is part of the
  module, not part of the setup.
- Namespace **`egress-demo`**, injected, with a `tester` client pod.
- **No `ServiceEntry`.**

### Outbound internet

The commands in this module reach `httpbin.org` and `example.com`. If your
environment has no outbound internet access, what you see will be network
errors rather than mesh decisions — check a plain `curl` from the node before
concluding Istio did something.

## Things to try

- Call two external hosts under the default policy and confirm both work, then
  run `istioctl install --set profile=demo --set meshConfig.outboundTrafficPolicy.mode=REGISTRY_ONLY -y`
  and confirm both now 502. That 502 is the mesh refusing, not the network.
- Register `httpbin.org` on port 80 and confirm `example.com` stays blocked.
- Declare the port as `protocol: TCP` instead of `HTTP`, then try to apply a
  `VirtualService` timeout to it and work out why nothing happens.
- Apply a `2s` timeout to `httpbin.org` and call `/delay/5`. A deadline on
  somebody else's API, enforced by your own sidecar.
- Add a `DestinationRule` with outlier detection for the external host and
  reason about what it would eject.
- Use a wildcard host (`*.github.com`) and see which calls it covers.
- Add a `Sidecar` resource whose `egress.hosts` excludes the external host, and
  watch a perfectly valid `ServiceEntry` stop working for that namespace. Same
  502, different cause.
- Set `exportTo: ["."]` and check the host disappears from another namespace's
  `istioctl proxy-config cluster`.

## When you're done

```sh
astrona destroy ats-014-playground-070-01
```

(`astrona destroy` takes the environment name, not the config path.)
