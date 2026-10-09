# Overview: Ingress With The Kubernetes Gateway API (Playground)

This is a **playground**, not a lab. It starts a new cluster, installs the Gateway API CRDs, Istio and the sample app, and then waits. There is no task, no `astrona submit` and no pass or fail. You can explore, break things, run `astrona destroy`, and start over.

## What is in the playground

The playground is one cluster with Istio and two namespaces of sample workloads. It has no Gateway API objects of its own, because creating them is the point of the module.

- A single-node `kind` Kubernetes cluster. `kubectl` already points at it.
- The **Gateway API custom resource definitions** (CRDs), version 1.3.0: `GatewayClass`, `Gateway`, `HTTPRoute`, `GRPCRoute` and `ReferenceGrant`. A CRD adds a new object kind to the Kubernetes API server. These kinds are not part of Kubernetes or Istio, so the playground installs them first.
- **Istio 1.30.5**, installed with Helm (`istio-base` and `istiod` only). `istiod` is Istio's control plane: it sends configuration to every proxy. There is **no ingress gateway**: every gateway in this playground is one you create with a Gateway API `Gateway`. Istio has registered the `GatewayClass` `istio`.
- Mesh-wide **access logs**: every Envoy proxy writes one log line per request. Read a gateway proxy's log with `kubectl logs -n starfleet deploy/<gateway name>-istio`.
- Namespace **`starfleet`**, labelled `istio-injection=enabled`, so every pod gets an `istio-proxy` sidecar. It holds:
  - The sample app: `bridge` (the web frontend, `/productpage`), `cargo`, `navcom`, and `scout` in three versions (`/reviews/0`).
  - **`shuttle`**, a client pod inside the mesh. You send every test request from it with `curl`.
- Namespace **`outpost`**, also with sidecar injection, with **`probe`** v1 and v2 on port `8000`. It is an HTTP echo server that answers with details of the request it received (`/hostname`, `/headers`). It stands for a second team in another namespace that wants to use your gateway.
- **No `Gateway` and no `HTTPRoute`.**
- The `bridge` page at `http://127.0.0.1:9080/productpage`. This port forward goes straight to the `bridge` Service, not through a gateway.

## Send a request through a gateway

When you create a `Gateway` named `starfleet-gateway`, Istio deploys a proxy for it and a Service named `starfleet-gateway-istio` in the same namespace. Send requests to that Service from the `shuttle` pod, with the host name your listener expects:

```sh
kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" \
  -H "Host: starfleet.example.com" http://starfleet-gateway-istio.starfleet/productpage
```

## Start over without a new cluster

These commands delete every `HTTPRoute` and `Gateway` and remove the `gateway-access` label from both namespaces:

```sh
kubectl delete httproute --all -A
kubectl delete gateway --all -A
kubectl label namespace starfleet outpost gateway-access-
```

Wait about half a minute before you create a `Gateway` with the same name again. If you create it sooner, it can stay at `Programmed=False` with the reason `AddressNotAssigned`.

## If the playground does not work

- `astrona list` shows the running environments. "already exists" means an old one is still there: run `astrona destroy ats-014-playground-060-03`, then run again.
- `astrona run` prints the full log path at the end (`~/.astrona/logs/`).
- If `kubectl` talks to another cluster, switch to this one: `kubectl config use-context kind-astro-ats-014-playground-060-03`.
- If a pod in `starfleet` or `outpost` shows `1/1` instead of `2/2`, it has no sidecar. Run `kubectl rollout restart deploy -n <namespace>`. A gateway's own pod always shows `1/1`, because it is a proxy with no application container.

When you are done, remove the playground. `astrona destroy` takes the environment name, not the configuration path:

```sh
astrona destroy ats-014-playground-060-03
```

## Practice tasks

Each task below is a small change to the files you saved while reading the module. Edit your saved file, apply it with `kubectl apply -f`, and read the status conditions.

- Change `gatewayClassName` in your `Gateway` to `istio-typo`. No controller takes the object: `PROGRAMMED` shows `Unknown`, the conditions say `Waiting for controller`, and no proxy appears.
- Leave out the `networking.istio.io/service-type: ClusterIP` annotation. The Service becomes a `LoadBalancer` stuck at `<pending>`, and the `Gateway` stays `Programmed=False AddressNotAssigned`.
- Add a second listener named `scout` on port `80` for the host name `scout.example.com`, and a route with `sectionName: scout` in its `parentRefs` that sends `/reviews` to `scout` on port `9080`. Requests for `scout.example.com` reach `scout`; the same path with `starfleet.example.com` gets `404`.
- Send `/productpage/x` and `/productpageX` through a route with `PathPrefix: /productpage`. Both answer `404`, but the gateway's access log shows the difference: `/productpage/x` reached the `bridge` Service (`via_upstream`), and `/productpageX` got `NR` from the gateway proxy.
- Switch `allowedRoutes` between `Same`, `All` and `Selector`, and watch the `Accepted` condition of the `outpost` route change.
- Run `istioctl analyze -n starfleet` while a route is broken. It reports a `False` condition as `IST0171`.
