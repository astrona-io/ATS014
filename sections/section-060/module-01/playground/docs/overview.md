# Overview: Expose A Service With An Istio Ingress Gateway (Playground)

> Declared in [`../config.yaml`](../config.yaml) under `metadata.docs.guide`.

This is a **playground**, not a lab: your training solar system, astronaut. It
starts a fresh cluster, installs Istio, an ingress gateway and the Starfleet,
and then waits. There is no task, no `astrona submit` and no pass or fail.
Explore, break things, `astrona destroy`, start over.

Until now, every signal came from a ship already in the fleet. Here, signals
arrive from outside the solar system. The **ingress gateway** is the spaceport
arrival gate: the one door that signals from outside come through.

## What's in the box

- A single-node `kind` Kubernetes cluster. `kubectl` is already pointed at it.
- **Istio 1.30.5**, installed with Helm. `istio-base` and `istiod` live in
  `istio-system`. `istiod` is mission control: it sends every proxy its orders.
- The **ingress gateway** on the planet `istio-ingress`. Its Deployment and
  its Service are both called `istio-ingress`, and its pods carry the label
  **`istio=ingress`**. A `Gateway` must select that label.
- Mesh-wide **access logs**, so every proxy writes one line per signal. Read
  the gate's flight log with
  `kubectl logs -n istio-ingress deploy/istio-ingress --tail=1`.
- Namespace **`starfleet`** (the planet you work on), labelled for injection, with:
  - **The Starfleet**: `bridge` (the flagship page, on `/productpage`),
    `cargo`, `navcom` and **`scout` in three versions**, all on port `9080`.
    Each `scout` answer names the pod that sent it (`"podname": "scout-v3-..."`).
  - The `scout` `DestinationRule` with the subsets `v1`, `v2` and `v3`.
  - **`probe`** v1 and v2 on port `8000`, an echo service.
  - **`shuttle`**, a client pod inside the mesh.
- **No `Gateway` and no `VirtualService`.** Writing them is the point of the
  module.

You also need `istioctl` 1.30.5 on your own machine for the `istioctl`
commands. Helm does not install it for you.

### Reaching the gateway

`kind` has no cloud load balancer, so nothing outside the cluster can reach
the gateway on its own. `astrona run` keeps two port forwards running for you.
A port forward is a tunnel from your machine into the cluster. If one drops,
astrona restarts it.

| Forward | Local | Goes to |
| --- | --- | --- |
| `ingress` | `http://127.0.0.1:8080` | the ingress gateway, port `80` |
| `bridge-ui` | `http://127.0.0.1:9080` | the bridge directly (no gateway) |

Check them with `astrona port-forward list`. You do not need to start a
`kubectl port-forward` yourself.

## Helper

Paste this into each new terminal. It sends one signal through the gateway for
a path, with a `Host` header (`starfleet.example.com` unless you name another
host), and prints only the status code:

```sh
gateway_status() { curl -s -o /dev/null -w "%{http_code}\n" -H "Host: ${2:-starfleet.example.com}" "http://localhost:8080$1"; }
```

Use it like this: `gateway_status /productpage`, or
`gateway_status /get probe.example.com`.

## Things to try

Each idea below is a small change to the files you made while reading the
module (`gateway-starfleet.yaml` and `virtualservice-bridge.yaml`). Edit your
saved file, apply it with `kubectl apply -f`, and watch what happens. The
module's parts show the full YAML for every step.

- Check the gateway pod's labels before writing anything:
  `kubectl get pods -n istio-ingress -L istio`.
- Apply only the `Gateway` and see `404` with the `NR` flag in the gate's
  flight log. Then add the `VirtualService` and watch `/productpage` become
  `200`, while `/admin` stays `404`.
- Change the `Gateway` selector to `istio: ingressgateway`. Every signal gets
  `000`, the port `80` listener disappears from
  `istioctl proxy-config listener deploy/istio-ingress -n istio-ingress`, and
  `istioctl analyze -n starfleet` reports `IST0101`.
- Remove `gateways:` from the `VirtualService`. The gate answers `404 NR`,
  its route table shows only `blackhole:80`, and `istioctl analyze` stays
  clean.
- Change the `VirtualService` host to `shop.example.com`. Both hosts get
  `404`, and `istioctl analyze` warns with `IST0132`.
- Set `hosts: ["*"]` on both objects. Now
  `curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8080/productpage`
  gets `200` with no `Host` header at all.
- Add a first rule that sends `/reviews/` to the `scout` subset `v3`, and
  count which scout answers `/reviews/0` through the gate.
- Compare `istioctl proxy-config routes deploy/istio-ingress -n istio-ingress`
  before and after each change.

For an exam-style task with a checked solution, see
[practice.md](./practice.md).

## Start over without a new cluster

```sh
kubectl delete gateways.networking.istio.io,virtualservice --all -n starfleet
```

## Playground not working?

- `astrona list` shows running environments. "already exists" means an old
  one is still there: `astrona destroy ats-014-playground-060-01`, then run
  again.
- The full log path is printed at the end of `astrona run` (`~/.astrona/logs/`).
- `kubectl` talks to another cluster:
  `kubectl config use-context kind-astro-ats-014-playground-060-01`.
- `gateway_status` prints `000` even with a correct `Gateway`: check the port
  forward with `astrona port-forward list`.

## When you're done

```sh
astrona destroy ats-014-playground-060-01
```

(`astrona destroy` takes the environment name, not the configuration path.)
