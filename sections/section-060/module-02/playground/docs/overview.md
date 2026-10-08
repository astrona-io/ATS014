# Overview: Expose A Service With A Kubernetes Ingress (Playground)

> Declared in [`../config.yaml`](../config.yaml) under `metadata.docs.guide`.

Welcome, astronaut. This is a **playground**, a training solar system, not a lab. The environment starts clean, runs
`bootstrap/prepare.sh`, applies the starting workloads, and then waits. There is
no task, no `astrona submit`, and no pass/fail. Explore, break things,
`astrona destroy`, start over.

Here you open the solar system to outside signals through the older
`Ingress` API, which Istio's gateway still accepts.

## What's in the box

- A single-node `kind` Kubernetes cluster with `kubectl` already pointed at it.
- **Istio 1.30.5** (`demo` profile), including the `istio-ingressgateway` in
  `istio-system`, plus `istioctl` on your PATH.
- Namespace **`k8s-ingress-demo`**, injected, with `booking-service` on port 80.
- **No `Ingress` and no `IngressClass`.**

### Reaching the gateway

```sh
kubectl -n istio-system port-forward svc/istio-ingressgateway 8080:80 >/dev/null 2>&1 &
export GATEWAY_URL=localhost:8080
```

## Things to try

- Apply an `Ingress` with no `ingressClassName` at all and confirm nothing serves
  it — `kubectl get ingress` shows an empty `CLASS` column and requests 404 with
  no error logged anywhere.
- Switch between `spec.ingressClassName: istio` and the legacy
  `kubernetes.io/ingress.class: istio` annotation and confirm both work.
- Test `pathType: Prefix` with `/book` against `/book`, `/book/123` and
  `/booking`. The last one does *not* match — `Prefix` is element-wise, unlike
  Istio's own `uri.prefix`.
- Create the TLS secret in `k8s-ingress-demo` instead of `istio-system` and watch
  the HTTPS listener never come up while HTTP keeps working. Then move it and
  watch it recover. This is the most common failure on this topic.
- Try to express a 90/10 weighted split in an `Ingress` and convince yourself
  there is nowhere to put it.
- Compare `istioctl proxy-config routes deploy/istio-ingressgateway -n istio-system`
  for an `Ingress` and for an equivalent `Gateway` + `VirtualService`. The
  translated output is very similar.

## When you're done

```sh
astrona destroy ats-014-playground-060-02
```

(`astrona destroy` takes the environment name, not the configuration path.)
