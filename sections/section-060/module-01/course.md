# Expose A Service With An Istio Ingress Gateway

<!-- astrona:playground -->
> [!NOTE]
> 🧪 **Hands-on playground for this module** — a clean, throwaway machine to explore on. No task, no grading. Folder: [`playground/`](https://github.com/astrona-io/ATS014/tree/main/sections/section-060/module-01/playground)
>
> ```sh
> astrona run --git ssh://git@github.com/astrona-io/ATS014.git -c sections/section-060/module-01/playground
> astrona destroy ats-014-playground-060-01
> ```

Everything so far has been **east-west** traffic: one workload in the mesh calling another, both with sidecars, both already inside. This section is about **north-south** traffic — requests arriving from outside the cluster entirely, from a browser or another system, with no sidecar and no membership in the mesh.

The entry point is a dedicated proxy pod, the **ingress gateway**. It is the same Envoy as every sidecar, but it runs standalone in `istio-system`, has no application container beside it, and is exposed through a Kubernetes Service. Configuring it takes two objects: one to open a listener, one to attach routes to that listener.

## How this module is organised

1. **[Part 1 — The Gateway Pod And Its Listener](./course-01-the-gateway-pod-and-its-listener.md)** — what the gateway is, how a `Gateway` object finds it, and what `servers[]` actually opens.
2. **[Part 2 — Binding Routes With `gateways:`](./course-02-binding-routes-with-gateways.md)** — the one field that separates north-south from east-west routing, the `mesh` reserved name, host overlap, and cross-namespace references.
3. **[Part 3 — Diagnosing The Gateway](./course-03-diagnosing-the-gateway.md)** — reading a 404 apart from a 503, inspecting the gateway's own configuration, and the module's pitfalls.

## Learning objectives

After this module you can:

- Explain what the ingress gateway pod is, where it runs, and how it differs from a sidecar.
- Write a `Gateway` that opens an HTTP listener for named hosts, and say what its `selector` matches.
- Bind a `VirtualService` to that listener with `gateways:`, and explain what the value `mesh` means.
- Predict the effect of a host mismatch between the two objects.
- Reference a `Gateway` from another namespace correctly.
- Distinguish a gateway 404 from a 503 and know which half of the configuration each points at.
- Inspect the gateway proxy's own listeners and routes.

## Before you start

You need `VirtualService` from section 010. Everything you know about `http` rules, matching and routing applies unchanged — the only new thing is that the rules now hang off a listener instead of applying inside the mesh.

The playground gives you a single-node `kind` cluster with **Istio 1.30.5 already installed** (the `demo` profile, which includes the ingress gateway) and the namespace **`ingress-demo`**, injected, containing `booking-service` on port 80. No `Gateway` and no `VirtualService` exist yet.

One environment detail matters throughout. A `kind` cluster has no cloud load balancer, so `kubectl -n istio-system get svc istio-ingressgateway` shows `EXTERNAL-IP: <pending>` forever. That is expected, not a fault. Reach the gateway with a port-forward and leave it running for the rest of the module:

```sh
kubectl -n istio-system port-forward svc/istio-ingressgateway 8080:80 >/dev/null 2>&1 &
export GATEWAY_URL=localhost:8080
```

On a real cloud cluster you would read the address out of `status.loadBalancer.ingress[0].ip` instead. The Istio objects are identical either way.

## Where this fits

This is the first of three ways to get north-south traffic into the mesh, and the other two in this section are best understood by contrast with it. The Kubernetes `Ingress` API (module 2) is the compatibility path for manifests that already exist, and the Kubernetes Gateway API (module 3) is the portable successor. All three end at the same `booking-service`; what differs is the API you write and what it can express.
