# Overview: Ingress With The Kubernetes Gateway API (Playground)

> Declared in [`../config.yaml`](../config.yaml) under `metadata.docs.guide`.

This is a **playground**, not a lab: your training solar system, astronaut. It
starts a fresh cluster, installs the Gateway API, Istio and the Starfleet, and
then waits. There is no task, no `astrona submit` and no pass or fail. Explore,
break things, `astrona destroy`, start over.

## What's in the box

- A single-node `kind` Kubernetes cluster. `kubectl` is already pointed at it.
- The **Gateway API objects** (version 1.3.0): `GatewayClass`, `Gateway`,
  `HTTPRoute`, `GRPCRoute` and `ReferenceGrant`. They are not part of
  Kubernetes or Istio, so the playground installs them first.
- **Istio 1.30.5**, installed with Helm (`istio-base` and `istiod` only). There
  is **no ingress gateway**: every gate in this playground is one you build with
  a Gateway API `Gateway`. Istio has registered the `GatewayClass` `istio`.
- Mesh-wide **access logs**, so every proxy writes one line per signal. Read a
  gate's flight log with `kubectl logs -n starfleet deploy/<gateway name>-istio`.
- Namespace **`starfleet`** (a planet), labelled `istio-injection=enabled`, with:
  - **The Starfleet**: `bridge` (the flagship page, `/productpage`), `cargo`,
    `navcom`, and `scout` in three versions (`/reviews/0`).
  - **`shuttle`**, your client pod inside the mesh. You send every test signal
    from it with `curl`.
- Namespace **`outpost`** (a second planet), also injected, with the **`probe`**
  v1 and v2 on port `8000`. It echoes what it receives (`/hostname`,
  `/headers`), and plays a second crew that wants to use your gate.
- **No `Gateway` and no `HTTPRoute`.** Building them is the point of the module.
- The bridge page at <http://127.0.0.1:9080/productpage>. This port forward
  goes straight to the bridge, not through a gate.

## Send a signal through a gate

A gate built from a `Gateway` named `starfleet-gateway` gets a Service named
`starfleet-gateway-istio` on the same planet. Send signals to it from the
shuttle, with the host name your listener expects:

```sh
kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" \
  -H "Host: starfleet.example.com" http://starfleet-gateway-istio.starfleet/productpage
```

## Things to try

Each idea below is a small change to the files you made while reading the
module. Edit your saved file, apply it with `kubectl apply -f`, and read the
status lights. The module's parts show the full YAML for every step.

- Change `gatewayClassName` in your `Gateway` to `istio-typo`. No controller
  takes it: `PROGRAMMED` shows `Unknown`, the conditions say
  `Waiting for controller`, and no proxy appears.
- Leave out the `networking.istio.io/service-type: ClusterIP` annotation. The
  Service becomes a `LoadBalancer` stuck at `<pending>`, and the `Gateway`
  stays `Programmed=False AddressNotAssigned`.
- Add a second listener named `scout` on port `80` for the host name
  `scout.example.com`, and a route with `sectionName: scout` in its
  `parentRefs` that sends `/reviews` to `scout` on port `9080`. Signals for
  `scout.example.com` reach the scout; the same path with
  `starfleet.example.com` gets `404`.
- Send `/productpage/x` and `/productpageX` through a route with
  `PathPrefix: /productpage`. Both answer `404`, but the gate's flight log
  shows the difference: `/productpage/x` reached the bridge (`via_upstream`),
  and `/productpageX` got `NR` from the gate.
- Switch `allowedRoutes` between `Same`, `All` and `Selector`, and watch the
  `outpost` route's `Accepted` condition change.
- Run `istioctl analyze -n starfleet` while a route is broken. It reports a
  `False` condition as `IST0171`.

## Start over without a new cluster

```sh
kubectl delete httproute --all -A
kubectl delete gateway --all -A
kubectl label namespace starfleet outpost gateway-access-
```

Wait about half a minute before you create a `Gateway` with the same name
again.

## Playground not working?

- `astrona list` shows running environments. "already exists" means an old
  one is still there: `astrona destroy ats-014-playground-060-03`, then run
  again.
- The full log path is printed at the end of `astrona run` (`~/.astrona/logs/`).
- `kubectl` talks to another cluster:
  `kubectl config use-context kind-astro-ats-014-playground-060-03`.
- A pod shows `1/1` instead of `2/2` in `starfleet` or `outpost`: it has no
  sidecar. Run `kubectl rollout restart deploy -n <namespace>`. A gate's own
  pod is always `1/1`.

## When you're done

```sh
astrona destroy ats-014-playground-060-03
```

(`astrona destroy` takes the environment name, not the configuration path.)
