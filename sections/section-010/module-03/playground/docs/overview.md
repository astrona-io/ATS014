# Overview: Apply And Remove Traffic Rules Safely (Playground)

> Declared in [`../config.yaml`](../config.yaml) under `metadata.docs.guide`.

This is a **playground**, not a lab: your training solar system. It starts a fresh cluster, installs Istio
and the Starfleet, and then waits. There is no task, no `astrona submit` and
no pass or fail. Explore, break things, `astrona destroy`, start over.

## What's in the box

- A single-node `kind` Kubernetes cluster. `kubectl` is already pointed at it.
- **Istio 1.30.5**, installed with Helm (`istio-base` and `istiod` only, no
  gateways). `istiod` is mission control: it radios new orders to every proxy.
- Mesh-wide **access logs**: every proxy writes one line per request, its
  flight log. Read it with `kubectl logs -n starfleet deploy/shuttle -c istio-proxy`.
- Namespace **`starfleet`** (the planet), labelled `istio-injection=enabled`, with
  the fleet: the flagship `bridge`, the supply ship `cargo`, the scout in three
  ship classes (`scout` v1, v2 and v3), the navigation computer `navcom`, your
  test client `shuttle`, and the echo `probe` v1/v2. It is the Istio docs'
  Bookinfo sample with space names; the paths inside a signal keep their old
  names, so the scout answers on `http://scout:9080/reviews/0`.
- **No `DestinationRule` and no `VirtualService`.** You apply them in the
  order the module teaches.
- The bridge's page at <http://127.0.0.1:9080/productpage>.

## Things to try

- Apply the "all to v1" route in [`../examples/`](../examples/) **before** the
  `DestinationRule`, then call `scout` straight away. Read the `503` and the
  `NC` flag in the flight log. Then apply the `DestinationRule` and call again.
- Run `istioctl proxy-status` after each change and wait for every proxy to
  show `SYNCED` before you test.
- Delete the `DestinationRule` while the `VirtualService` still uses it.
  That is "break before make" in reverse. Then do it the right way round.
- Apply the same `VirtualService` file twice with a different subset. See that
  `kubectl apply` replaces the object rather than adding a second one.
- Check a default with no rules at all: call
  `http://probe:8000/delay/3` and see that nothing times out.

## Start over without a new cluster

```sh
kubectl delete virtualservice,destinationrule --all -n starfleet
```

## Playground not working?

- `astrona list` shows running environments. "already exists" means an old one
  is still there: `astrona destroy ats-014-playground-010-03`, then run again.
- The full log path is printed at the end of `astrona run` (`~/.astrona/logs/`).
- `kubectl` talks to another cluster:
  `kubectl config use-context kind-astro-ats-014-playground-010-03`.
- A pod shows `1/1` instead of `2/2`: it has no sidecar. Run
  `kubectl rollout restart deploy -n starfleet`.

## When you're done

```sh
astrona destroy ats-014-playground-010-03
```

(`astrona destroy` takes the environment name, not the configuration path.)
