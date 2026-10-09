# Overview: Expose A Service With A Kubernetes Ingress (Playground)

This is a playground, not a lab. It starts a fresh cluster, installs Istio, its ingress gateway and the example workloads, and then waits. There is no task, no `astrona submit` and no pass or fail. You can explore, break things, run `astrona destroy` and start over.

Here you expose Services to traffic from outside the cluster with the Kubernetes `Ingress` API. An `Ingress` is an object that describes how HTTP requests for a host and a path reach a Service inside the cluster. Istio's ingress gateway, an Envoy proxy at the edge of the mesh, can serve it.

## What's in the box

The playground holds one cluster with Istio, the gateway and the example workloads:

- A single-node `kind` Kubernetes cluster. `kubectl` already points at it.
- **Istio 1.30.5**, installed with Helm: `istio-base`, `istiod` (Istio's control plane, which sends configuration to every proxy) and the **ingress gateway** `istio-ingressgateway` in `istio-system`. Its pods carry the label `istio: ingressgateway`, which marks the gateway Istio uses for every `Ingress` by default.
- Mesh-wide **access logs**: every proxy writes one line per request. Read the gateway's log with `kubectl logs -n istio-system deploy/istio-ingressgateway`.
- Namespace **`starfleet`**, labelled `istio-injection=enabled`, with:
  - `bridge`, the web frontend (its page is `/productpage` on port `9080`), and the backends it calls: `cargo`, `navcom` and `scout` v1/v2/v3.
  - **`probe`** v1 and v2, an HTTP echo server on port `8000`. It answers any path under `/anything`, so a `404` on such a path came from the gateway, not from the `probe` pod.
  - **`shuttle`**, a test client pod inside the mesh.
- **No `IngressClass` and no `Ingress`.** Writing them is the point of the module.

## Reaching the gateway

The playground forwards two ports on your machine to the gateway:

| On your machine | Gateway port |
| --- | --- |
| `http://localhost:8080` | `80` |
| `https://localhost:8443` | `443` (once a TLS `Ingress` and its secret exist) |

Paste this once in each new terminal:

```sh
GATEWAY_URL=localhost:8080
```

Send requests with the host that your `Ingress` names, for example `curl -s -o /dev/null -w '%{http_code}\n' -H "Host: starfleet.example.com" http://$GATEWAY_URL/productpage`. For HTTPS, add `--resolve starfleet.example.com:8443:127.0.0.1`, so curl sends the right name in the TLS (Transport Layer Security) handshake.

## Start over without a new cluster

These commands remove every `Ingress`, the `istio` class and the TLS secret:

```sh
kubectl delete ingress --all -n starfleet
kubectl delete ingressclass istio
kubectl delete secret starfleet-credential -n istio-system --ignore-not-found
```

## Playground not working?

- `astrona list` shows the running environments. If `astrona run` says "already exists", an old one is still there: run `astrona destroy ats-014-playground-060-02`, then run again.
- `astrona run` prints the full log path at the end (`~/.astrona/logs/`).
- If `kubectl` talks to another cluster, switch back: `kubectl config use-context kind-astro-ats-014-playground-060-02`.
- If `curl` prints `000` on port `8080`, no `Ingress` is served yet, so the gateway has no listener on port `80`. Check the `CLASS` column of `kubectl get ingress -n starfleet`.

## When you're done

`astrona destroy` takes the environment name, not the configuration path:

```sh
astrona destroy ats-014-playground-060-02
```

## Practice tasks

The `starfleet` namespace must stay reachable from outside while you change how its `Ingress` is written. Each task is a small change to the files you made while reading the module. Edit your saved file (for example `ingress-starfleet.yaml`), apply it with `kubectl apply -f`, and watch what happens.

1. Remove `ingressClassName` from your `Ingress`. The `CLASS` column shows `<none>`, and the gateway stops answering for that host.
2. Replace `ingressClassName` with the older annotation `kubernetes.io/ingress.class: istio`. Requests get through again, but the `CLASS` column still shows `<none>`.
3. Change a path's `pathType` from `Prefix` to `Exact` and send requests to a path below it. They get `404 NR` in the gateway's access log.
4. Try to write a 90/10 split between `probe` v1 and v2 in an `Ingress`. `kubectl explain ingress.spec.rules.http.paths.backend` shows that there is no field for a weight.
5. Compare `istioctl proxy-config routes deploy/istio-ingressgateway -n istio-system` before and after you apply an `Ingress`.
