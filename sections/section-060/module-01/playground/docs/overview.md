# Overview: Expose A Service With An Istio Ingress Gateway (Playground)

> Declared in [`../config.yaml`](../config.yaml) under `metadata.docs.guide`.

This is a **playground**, not a lab. The environment starts clean, runs
`bootstrap/prepare.sh`, applies the starting workloads, and then waits. There is
no task, no `astrona submit`, and no pass/fail. Explore, break things,
`astrona destroy`, start over.

## What's in the box

- A single-node `kind` Kubernetes cluster with `kubectl` already pointed at it.
- **Istio 1.30.5** installed with the `demo` profile, which includes the
  **`istio-ingressgateway`** Deployment and Service in `istio-system`.
- Namespace **`ingress-demo`**, injected, with `booking-service` on port 80.
- **No `Gateway` and no `VirtualService`**, so the gateway answers 404.

### Reaching the gateway

`kind` has no cloud load balancer, so `istio-ingressgateway` shows
`EXTERNAL-IP: <pending>` permanently. That is expected. Use a port-forward:

```sh
kubectl -n istio-system port-forward svc/istio-ingressgateway 8080:80 >/dev/null 2>&1 &
export GATEWAY_URL=localhost:8080
```

## Things to try

- Curl the gateway before creating anything and confirm the 404 comes from a
  perfectly healthy proxy with nothing configured.
- Create only the `Gateway` (no `VirtualService`) and confirm you still get 404.
  A listener with no routes serves nothing.
- Create the `VirtualService` but leave out `gateways:` entirely. Still 404 —
  the routes attached to the mesh instead. This is the classic mistake.
- Send a request with a `Host` the listener does not accept, and one with a path
  no rule matches. Both are 404 from different causes; find each in
  `istioctl proxy-config routes deploy/istio-ingressgateway -n istio-system`.
- Point `destination.host` at a service that does not exist and watch the 404
  turn into a 503. That is the boundary between "my config" and "my backend".
- Set `hosts: ["*"]` on both objects and confirm any `Host` header now works.
- Move the `Gateway` into `istio-system`, reference it as
  `istio-system/booking-gateway`, then drop the prefix and watch it break.
- Add a second `VirtualService` for a different path on the same `Gateway`.

## When you're done

```sh
astrona destroy ats-014-playground-060-01
```

(`astrona destroy` takes the environment name, not the config path.)
