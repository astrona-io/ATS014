# Overview: Route Requests By Header, URI And Query Parameter (Playground)

> Declared in [`../config.yaml`](../config.yaml) under `metadata.docs.guide`.

This is a **playground**, not a lab. The environment starts clean, runs
`bootstrap/prepare.sh`, applies the starting workloads, and then waits. There is
no task, no `astrona submit`, and no pass/fail. Explore, break things,
`astrona destroy`, start over.

## What's in the box

- A single-node `kind` Kubernetes cluster. `kubectl` is already pointed at it.
- **Istio 1.30.5**, installed with the `demo` profile, plus `istioctl` on your
  PATH. Confirm with `istioctl version`.
- Namespace **`routing-demo`**, labelled `istio-injection=enabled`, containing:
  - `notification-service-v1` and `notification-service-v2` — two Deployments
    of the same app, distinguished by a `version` label.
  - `notification-service` — one Service selecting on `app` only, so both
    versions are endpoints of it.
  - `tester` — a client pod with `curl` in it.
- Every pod runs `2/2`: the app container plus the injected `istio-proxy`.
- **No `VirtualService` and no `DestinationRule`.** Writing them is the point of
  the module, so nothing routes yet.

## Things to try

- Send the same request twenty times from `tester` and count the answers. Then
  add the `DestinationRule` alone and send them again — the split is unchanged,
  because subsets are vocabulary, not behaviour.
- Write a `VirtualService` with the default (no-`match`) rule **first** and watch
  every header rule below it become dead code, with no error anywhere.
- Reference a subset name that no `DestinationRule` defines, send a request, and
  see the bare 503. Then run `istioctl analyze -n routing-demo` and see it named.
- Write `exact: true` instead of `exact: "true"` for the header value and work
  out from the behaviour why the rule never fires.
- Compare `istioctl proxy-config routes deploy/tester -n routing-demo` before and
  after applying the `VirtualService`.
- Create the `VirtualService` in `default` instead of `routing-demo` and explain
  why nothing happens.

## When you're done

```sh
astrona destroy ats-014-playground-010-01
```

(`astrona destroy` takes the environment name, not the config path.)
