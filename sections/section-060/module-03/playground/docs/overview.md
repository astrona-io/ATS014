# Overview: Ingress With The Kubernetes Gateway API (Playground)

> Declared in [`../config.yaml`](../config.yaml) under `metadata.docs.guide`.

Welcome, astronaut. This is a **playground**, a training solar system, not a lab. The environment starts clean, runs
`bootstrap/prepare.sh`, applies the starting workloads, and then waits. There is
no task, no `astrona submit`, and no pass/fail. Explore, break things,
`astrona destroy`, start over.

Here you build a spaceport with the Gateway API: the `Gateway` object builds
its own arrival gate, and routes from other planets (namespaces) may dock only
if you allow them.

## What's in the box

- A single-node `kind` Kubernetes cluster with `kubectl` already pointed at it.
- **Istio 1.30.5** (`demo` profile) and `istioctl` on your PATH.
- **Gateway API CRDs v1.3.0**, installed by `bootstrap/prepare.sh`. They are not
  part of core Kubernetes; without them every apply fails with
  `no matches for kind "Gateway"`, which looks like an Istio error and is not.
- A `GatewayClass` named **`istio`**, registered by Istio itself.
- Namespace **`gwapi-demo`**, injected, with `booking-service` on port 80.
- **No `Gateway` and no `HTTPRoute`** — and therefore no gateway proxy at all,
  because under this API a Gateway creates its own.

## Things to try

- Create the `Gateway` and watch `booking-gateway-istio` appear as a Deployment
  and Service **in `gwapi-demo`**, not in `istio-system`.
- Delete the `Gateway` and watch the Deployment disappear with it. The proxy's
  lifecycle is tied to the object.
- Create the `HTTPRoute` in a different namespace while the Gateway says
  `allowedRoutes.namespaces.from: Same`, then read
  `status.parents[0].conditions` and find `Accepted=False` with the reason.
  Switch to `All` and watch it attach.
- Point a `backendRefs` entry at a Service that does not exist and find
  `ResolvedRefs=False`.
- Break the object deliberately (a bad `gatewayClassName`) and compare
  `Accepted=False` against `Accepted=True, Programmed=False`. They mean
  different things: your YAML versus the infrastructure.
- Add a second `parentRefs` entry and serve the same route through two Gateways.
- Express the section 020 weighted split with two `backendRefs` weights.
- Translate a `VirtualService` you wrote earlier into an `HTTPRoute` field by
  field, and note what has no equivalent — everything on the `DestinationRule`
  side stays an Istio object.

## When you're done

```sh
astrona destroy ats-014-playground-060-03
```

(`astrona destroy` takes the environment name, not the configuration path.)
