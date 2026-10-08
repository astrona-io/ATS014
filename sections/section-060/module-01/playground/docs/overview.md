# Overview: Expose A Service With An Istio Ingress Gateway (Playground)

> Declared in [`../config.yaml`](../config.yaml) under `metadata.docs.guide`.

Welcome, astronaut. This is a **playground**, a training solar system, not a lab. The environment starts clean, installs
Istio and Bookinfo, and then waits. There is no task, no `astrona submit`, and
no pass/fail. Explore, break things, `astrona destroy`, start over.

Think of the mesh as a fleet of ships. Until now, every signal came from a
ship already in the fleet. Here, signals arrive from outside the solar system.
The **ingress gateway** is the spaceport arrival gate: the one door that
signals from outside come through.

## What's in the box

- A single-node `kind` Kubernetes cluster. `kubectl` is already pointed at it
  (context `kind-astro-ats-014-playground-060-01`).
- **Istio 1.30.5**, installed with Helm:
  - `istio-base` and `istiod` in namespace `istio-system`.
  - The **ingress gateway** in namespace `istio-ingress`. Its Deployment and
    Service are both called `istio-ingress`, and its pods carry the label
    **`istio=ingress`**. That label matters: a `Gateway` must select it.
- Namespace **`bookinfo`**, labelled for injection, with:
  - **Bookinfo**: `productpage`, `details`, `reviews` v1/v2/v3 and `ratings`,
    all on port 9080.
  - `httpbin` v1/v2 on port 8000, and a `curl` client pod.
  - The `reviews` DestinationRule with subsets `v1`, `v2` and `v3`.
- Access logs turned on for the whole mesh, so every proxy writes one line
  per request.
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
| `ingress` | `http://127.0.0.1:8080` | ingress gateway, port 80 |
| `bookinfo-ui` | `http://127.0.0.1:9080` | `productpage` directly (no gateway) |

Check them with `astrona port-forward list`. You do not need to start a
`kubectl port-forward` yourself.

### Helper

Paste this into each new terminal. It prints the status code for a path, sent
through the gateway with a `Host` header (default `bookinfo.example.com`):

```sh
gateway_status() { curl -s -o /dev/null -w "%{http_code}\n" -H "Host: ${2:-bookinfo.example.com}" "http://localhost:8080$1"; }
# gateway_status /productpage                       Host: bookinfo.example.com
# gateway_status /get httpbin.example.com           Host: httpbin.example.com
```

## Things to try

The module's parts walk through these step by step. The files are in
[`../examples/`](../examples/). Run the `kubectl apply -f` commands from this
playground folder in a clone of the repository.

- Check the gateway pod's labels before writing anything:
  `kubectl get pods -n istio-ingress --show-labels`.
- Apply only the `Gateway` (`examples/01-gateway-bookinfo.yaml`) and see
  `404` with the `NR` flag in the gateway's log
  (`kubectl logs -n istio-ingress deploy/istio-ingress --tail=1`).
- Add the linked `VirtualService` (`examples/02-virtualservice-bookinfo.yaml`)
  and watch `/productpage` become `200`, while `/admin` stays `404`.
- Apply `examples/03-virtualservice-bookinfo-with-reviews-api.yaml` and see
  `/reviews/0` from outside always answered by `reviews-v3`.
- Add `127.0.0.1 bookinfo.example.com` to `/etc/hosts` and open
  <http://bookinfo.example.com:8080/productpage> in a browser.
- Compare `istioctl proxy-config routes deploy/istio-ingress -n istio-ingress`
  before and after each change.

## Cases to test

Start each case from the working gateway:

```sh
kubectl apply -f examples/01-gateway-bookinfo.yaml -f examples/02-virtualservice-bookinfo.yaml
```

| Case | Apply | What you should see | Why |
| --- | --- | --- | --- |
| 1 – accept any host | `examples/cases/c1-gateway-and-virtualservice-any-host.yaml` | `curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8080/productpage` gives `200` with no `Host` header | `"*"` on both objects accepts every host |
| 2 – no `gateways:` | `examples/cases/c2-virtualservice-without-gateways.yaml` | `gateway_status /productpage` gives `404`, log flag `NR`, and `istioctl analyze -n bookinfo` finds nothing | Without `gateways:`, the rules go to the sidecars (`mesh`), not the gateway |
| 3 – wrong selector | `examples/cases/c3-gateway-wrong-selector.yaml` | `gateway_status /productpage` gives `000` (empty reply), and `istioctl analyze -n bookinfo` reports `IST0101` | No pod has `istio=ingressgateway`, so nothing listens on port 80 |
| 4 – host not on the Gateway | `examples/cases/c4-virtualservice-host-not-on-gateway.yaml` | `404` for both hosts, and `istioctl analyze -n bookinfo` reports `IST0132` | The two host lists must overlap |

Back to the working state:

```sh
kubectl apply -f examples/01-gateway-bookinfo.yaml -f examples/02-virtualservice-bookinfo.yaml
```

## Practice

Ready for an exam-style task? Try [practice.md](practice.md): expose `httpbin`
on its own host with only two paths open.

## Start over without a new cluster

```sh
kubectl delete gateways.networking.istio.io --all -n bookinfo
kubectl delete virtualservice --all -n bookinfo
```

## When you're done

```sh
astrona destroy ats-014-playground-060-01
```

(`astrona destroy` takes the environment name, not the configuration path.)
