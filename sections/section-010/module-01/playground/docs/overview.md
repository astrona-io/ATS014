# Overview: Route Requests Within The Mesh (Playground)

> Declared in [`../config.yaml`](../config.yaml) under `metadata.docs.guide`.

This is a **playground**, not a lab: your training solar system, astronaut. It
starts a fresh cluster, installs Istio and the Starfleet, and then waits. There is no task, no `astrona submit` and
no pass or fail. Explore, break things, `astrona destroy`, start over.

## What's in the box

- A single-node `kind` Kubernetes cluster. `kubectl` is already pointed at it.
- **Istio 1.30.5**, installed with Helm (`istio-base` and `istiod` only, no
  gateways). `istiod` is mission control: it sends every proxy its orders.
- Mesh-wide **access logs**, so every proxy writes one line per request. This
  is the ship's flight log, and you read it with
  `kubectl logs -n starfleet deploy/shuttle -c istio-proxy`.
- Namespace **`starfleet`** (the planet you work on), labelled `istio-injection=enabled`, with:
  - **The Starfleet** (the Istio docs' Bookinfo sample with space names): `bridge`
    (the flagship page), `cargo` (supply ship), `navcom` (navigation computer)
    and **`scout` in three versions**. v1 shows no stars, v2 black stars,
    v3 red stars. Each `scout` answer names the pod that sent it
    (`"podname": "scout-v2-..."`), which is how you see the version.
  - **`shuttle`**, your client pod inside the mesh. You send every test signal
    from it with the `curl` command.
  - **`probe`** v1 and v2 behind one Service on port `8000`. It echoes what
    it receives (`/headers`, `/anything`), so the rewriting and non-HTTP parts can show what the
    proxy changed.
- Every pod (spaceship) shows `2/2`: the app plus its `istio-proxy` sidecar,
  the communications officer that every signal in or out goes through.
- **No `DestinationRule` and no `VirtualService`.** Writing them is the point
  of the module, so nothing is routed yet.
- The bridge page at <http://127.0.0.1:9080/productpage>. Refresh it to see
  the stars change. Log in as `jason` (any password) and the bridge sends the
  header `end-user: jason` on to `scout`.
- The web paths inside the ships keep their original names: a signal to the
  scout goes to `http://scout:9080/reviews/0`.

## Helpers

Paste this once in each new terminal. `count_versions` sends 10 requests and
counts which `scout` version answered. Any `curl` options you give it are
passed on.

```sh
count_versions() { for i in $(seq 1 10); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s "$@" | grep -o 'scout-v[0-9]' || echo none
done | sort | uniq -c; }
SCOUT=http://scout:9080/reviews
```

Use it like this: `count_versions $SCOUT/0`, or
`count_versions -H "end-user: jason" $SCOUT/0`.

## Things to try

Each idea below is a small change to the files you made while reading the
module. Edit your saved file (for example `virtualservice-scout.yaml`), apply
it with `kubectl apply -f`, and watch what happens. The module's parts show the
full YAML for every step.

- Run `count_versions $SCOUT/0` with no rules at all. All three versions
  answer. Then apply only the `DestinationRule` with the three subsets and run
  it again. Nothing changes: docking instructions alone steer no signal.
- In your `VirtualService`, change the subset to `v4`, a name the
  `DestinationRule` does not define. Read the `503` and the `NC` flag in the
  access log, then run `istioctl analyze -n starfleet`.
- Put the subset back to `v1`, and instead change the `v1` subset's label in
  the `DestinationRule` to `version: v9`. You get `503` again, but this time
  with `UH`.
- In the jason rule's `VirtualService`, move the catch-all route to the top.
  The jason rule goes dead, and `istioctl analyze` warns with `IST0130`.
- Remove the catch-all route completely and send a signal without the jason
  header. You get a `404` with the `NR` flag, and `analyze` says nothing.
- Write a `match` with a header and a path in one item, then split them into
  two items. One `-` is the only difference between AND and OR.
- Compare `istioctl proxy-config routes deploy/shuttle -n starfleet --name 9080`
  before and after applying a `VirtualService`.

Apply the `scout` `DestinationRule` first. Every `VirtualService` here sends
signals to its subsets.

For exam-style practice with checked solutions, see
[practice.md](./practice.md).

## Start over without a new cluster

```sh
kubectl delete virtualservice,destinationrule --all -n starfleet
```

## Playground not working?

- `astrona list` shows running environments. "already exists" means an old
  one is still there: `astrona destroy ats-014-playground-010-01`, then run
  again.
- The full log path is printed at the end of `astrona run` (`~/.astrona/logs/`).
- `kubectl` talks to another cluster:
  `kubectl config use-context kind-astro-ats-014-playground-010-01`.
- A pod shows `1/1` instead of `2/2`: it has no sidecar. Run
  `kubectl rollout restart deploy -n starfleet`.

## When you're done

```sh
astrona destroy ats-014-playground-010-01
```

(`astrona destroy` takes the environment name, not the configuration path.)
