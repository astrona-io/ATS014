# Overview: Expose A Service With A Kubernetes Ingress (Playground)

> Declared in [`../config.yaml`](../config.yaml) under `metadata.docs.guide`.

This is a **playground**, not a lab: your training solar system, astronaut. It
starts a fresh cluster, installs Istio, its ingress gateway and the Starfleet,
and then waits. There is no task, no `astrona submit` and no pass or fail.
Explore, break things, `astrona destroy`, start over.

Here you open the solar system to outside signals through the older Kubernetes
`Ingress` API, which Istio's gateway still accepts.

## What's in the box

- A single-node `kind` Kubernetes cluster. `kubectl` is already pointed at it.
- **Istio 1.30.5**, installed with Helm: `istio-base`, `istiod` (mission
  control) and the **ingress gateway** `istio-ingressgateway` in `istio-system`.
  Its pods carry the label `istio: ingressgateway`, the gate Istio uses for
  every `Ingress` by default.
- Mesh-wide **access logs**. The gate's flight log is
  `kubectl logs -n istio-system deploy/istio-ingressgateway`.
- Namespace **`starfleet`** (the planet you work on), labelled `istio-injection=enabled`, with:
  - **The Starfleet**: `bridge` (the flagship, its page is `/productpage` on
    port `9080`), `cargo`, `navcom` and `scout` v1/v2/v3.
  - **`probe`** v1 and v2 on port `8000`. It answers any path under
    `/anything`, so a `404` on such a path came from the gate, not the probe.
  - **`shuttle`**, your client pod inside the mesh.
- **No `IngressClass` and no `Ingress`.** Writing them is the point of the module.

### Reaching the gate

The playground forwards two ports on your machine to the gate:

| On your machine | Gateway port |
| --- | --- |
| `http://localhost:8080` | `80` |
| `https://localhost:8443` | `443` (once a TLS `Ingress` and its secret exist) |

Paste this once in each new terminal:

```sh
GATEWAY_URL=localhost:8080
```

Send signals with the host your `Ingress` names, for example
`curl -s -o /dev/null -w '%{http_code}\n' -H "Host: starfleet.example.com" http://$GATEWAY_URL/productpage`.
For HTTPS, use `--resolve starfleet.example.com:8443:127.0.0.1` so curl sends
the right name in the TLS handshake.

## Things to try

Each idea is a small change to the files you made while reading the module.
Edit your saved file (for example `ingress-starfleet.yaml`), apply it with
`kubectl apply -f`, and watch what happens.

- Remove `ingressClassName` from your `Ingress`. The `CLASS` column shows
  `<none>` and the gate stops answering for that host.
- Replace `ingressClassName` with the older annotation
  `kubernetes.io/ingress.class: istio`. Signals get through again, but the
  `CLASS` column still shows `<none>`.
- Change a path's `pathType` from `Prefix` to `Exact` and send signals to a
  path below it. They get `404 NR` in the gate's flight log.
- Try to write a 90/10 split between `probe` v1 and v2 in an `Ingress`.
  `kubectl explain ingress.spec.rules.http.paths.backend` shows there is
  nowhere to put a weight.
- Compare `istioctl proxy-config routes deploy/istio-ingressgateway -n istio-system`
  before and after applying an `Ingress`.

## Start over without a new cluster

```sh
kubectl delete ingress --all -n starfleet
kubectl delete ingressclass istio
kubectl delete secret starfleet-credential -n istio-system --ignore-not-found
```

## Playground not working?

- `astrona list` shows running environments. "already exists" means an old
  one is still there: `astrona destroy ats-014-playground-060-02`, then run
  again.
- The full log path is printed at the end of `astrona run` (`~/.astrona/logs/`).
- `kubectl` talks to another cluster:
  `kubectl config use-context kind-astro-ats-014-playground-060-02`.
- `curl` prints `000` on port `8080`: no `Ingress` is claimed yet, so the gate
  has no orders for port `80`. Check the `CLASS` column of `kubectl get ingress -n starfleet`.

## When you're done

```sh
astrona destroy ats-014-playground-060-02
```

(`astrona destroy` takes the environment name, not the configuration path.)
