# Overview: Route Requests Within The Mesh (Playground)

> Declared in [`../config.yaml`](../config.yaml) under `metadata.docs.guide`.

This is a **playground**, not a lab: your training solar system, astronaut. It
starts a fresh cluster, installs Istio and the Bookinfo app, and then waits. There is no task, no `astrona submit` and
no pass or fail. Explore, break things, `astrona destroy`, start over.

## What's in the box

- A single-node `kind` Kubernetes cluster. `kubectl` is already pointed at it.
- **Istio 1.30.5**, installed with Helm (`istio-base` and `istiod` only, no
  gateways). `istiod` is mission control: it sends every proxy its orders.
- Mesh-wide **access logs**, so every proxy writes one line per request. This
  is the ship's flight log, and you read it with
  `kubectl logs -n bookinfo deploy/curl -c istio-proxy`.
- Namespace **`bookinfo`** (the planet you work on), labelled `istio-injection=enabled`, with:
  - **Bookinfo**, a small book shop app: `productpage`, `details`, `ratings`
    and **`reviews` in three versions**. v1 shows no stars, v2 black stars,
    v3 red stars. Each `reviews` answer names the pod that sent it
    (`"podname": "reviews-v2-..."`), which is how you see the version.
  - **`curl`**, a client pod inside the mesh. You send test requests from it.
  - **`httpbin`** v1 and v2 behind one Service on port `8000`. It echoes what
    it receives (`/headers`, `/anything`), so parts 4 and 5 can show what the
    proxy changed.
- Every pod (spaceship) shows `2/2`: the app plus its `istio-proxy` sidecar,
  the communications officer that every signal in or out goes through.
- **No `DestinationRule` and no `VirtualService`.** Writing them is the point
  of the module, so nothing is routed yet.
- The Bookinfo page at <http://127.0.0.1:9080/productpage>. Refresh it to see
  the stars change. Log in as `jason` (any password) and productpage sends the
  header `end-user: jason` on to `reviews`.

## Helpers

Paste this once in each new terminal. `count_versions` sends 10 requests and
counts which `reviews` version answered. Any curl options you give it are
passed on.

```sh
count_versions() { for i in $(seq 1 10); do
  kubectl exec -n bookinfo deploy/curl -- curl -s "$@" | grep -o 'reviews-v[0-9]' || echo none
done | sort | uniq -c; }
REVIEWS=http://reviews:9080/reviews
```

Use it like this: `count_versions $REVIEWS/0`, or
`count_versions -H "end-user: jason" $REVIEWS/0`.

## Things to try

The YAML for each idea is in [`../examples/`](../examples/). The module's
parts walk through the same files step by step.

- Run `count_versions $REVIEWS/0` with no rules at all. All three versions
  answer. Then apply only the `DestinationRule`
  (`examples/01-request-routing/01-destinationrule-reviews-subsets.yaml`) and
  run it again. Nothing changes: docking instructions alone steer no signal.
- Apply `examples/01-request-routing/cases/c2-virtualservice-subset-typo.yaml`
  and read the `503` and the `NC` flag in the access log. Then run
  `istioctl analyze -n bookinfo`.
- Apply `examples/01-request-routing/cases/c3-destinationrule-label-mismatch.yaml`
  with the "all to v1" rule in place and compare: `503` again, but `UH`.
- Apply `examples/02-header-based-routing/02-virtualservice-reviews-wrong-order.yaml`
  and watch the jason rule go dead. `istioctl analyze` warns with `IST0130`.
- Apply `examples/02-header-based-routing/cases/c6-virtualservice-no-catch-all.yaml`
  and see a `404` with the `NR` flag. This time `analyze` says nothing.
- Compare `examples/02-header-based-routing/cases/c3-virtualservice-and-match.yaml`
  with `c4-virtualservice-or-match.yaml`. One `-` is the only difference.
- Compare `istioctl proxy-config routes deploy/curl -n bookinfo --name 9080`
  before and after applying a `VirtualService`.

The cases in `examples/02-header-based-routing/` need the `reviews`
`DestinationRule` from `examples/01-request-routing/` applied first.

For exam-style practice with checked solutions, see
[practice.md](./practice.md).

## Start over without a new cluster

```sh
kubectl delete virtualservice,destinationrule --all -n bookinfo
```

## Playground not working?

- `astrona list` shows running environments. "already exists" means an old
  one is still there: `astrona destroy ats-014-playground-010-01`, then run
  again.
- The full log path is printed at the end of `astrona run` (`~/.astrona/logs/`).
- `kubectl` talks to another cluster:
  `kubectl config use-context kind-astro-ats-014-playground-010-01`.
- A pod shows `1/1` instead of `2/2`: it has no sidecar. Run
  `kubectl rollout restart deploy -n bookinfo`.

## When you're done

```sh
astrona destroy ats-014-playground-010-01
```

(`astrona destroy` takes the environment name, not the configuration path.)
