# Expose A Service With An Istio Ingress Gateway

<!-- astrona:playground -->
> [!NOTE]
> 🧪 **Hands-on playground for this module** — a clean, throwaway machine to explore on. No task, no grading. Folder: `playground/`
>
> ```sh
> astrona run --git ssh://git@github.com/astrona-io/ATS014.git -c sections/section-060/module-01/playground
> astrona destroy ats-014-playground-060-01
> ```

Astronaut, so far every signal you routed was **east-west** traffic: one spaceship in the mesh signalling another. Think of the mesh as a fleet of ships that all talk over the same signal network, and of the cluster as your solar system. Both sides of every call were already ships in the fleet. This mission is about **north-south** traffic: signals that arrive from outside your solar system, from a browser or another system. They have no communications officer (sidecar) on board and are not part of the mesh.

These signals come in through the **ingress gateway**. Picture it as the spaceport arrival gate: the one door that signals from outside the solar system come through. It is the same Envoy proxy that runs as every sidecar. But it runs on its own, with no app container beside it, and a Kubernetes Service puts it in front of the outside world. You set it up with two objects: a `Gateway` opens the gate, and a `VirtualService` linked to it says where traffic goes next.

## How this module is organised

1. **[The Gateway Pod And Its Listener](./course-01-the-gateway-pod-and-its-listener.md)** — what the gateway is, how a `Gateway` object finds it, and what `servers[]` actually opens.
2. **[Binding Routes With `gateways:`](./course-02-binding-routes-with-gateways.md)** — the one field that separates north-south from east-west routing, the `mesh` reserved name, host overlap, and cross-namespace references.
3. **[Diagnosing The Gateway](./course-03-diagnosing-the-gateway.md)** — telling a failed connection, a 404 and a 503 apart, inspecting the gateway's own configuration, and the module's pitfalls.

## Learning objectives

After this module you can:

- Explain what the ingress gateway pod is, where it runs, and how it differs from a sidecar.
- Write a `Gateway` that opens an HTTP listener for named hosts, and say what its `selector` matches.
- Find the right `selector` labels for your install, because Helm and `istioctl` label the gateway pods differently.
- Bind a `VirtualService` to that listener with `gateways:`, and explain what the value `mesh` means.
- Predict the effect of a host mismatch between the two objects.
- Reference a `Gateway` from another namespace correctly.
- Tell apart a failed connection (`000`), a gateway 404 and a 503, and know which part of the setup each one points at.
- Inspect the gateway proxy's own listeners and routes.

## Before you start

This module assumes [section 000](../../section-000/module-01/course.md): a proxy beside every pod, `istiod` programming it over xDS, and `istioctl proxy-config` as the way to see what a proxy actually holds rather than what you hoped it holds.

You need `VirtualService` from section 010. Everything you know about `http` rules, matching and routing applies unchanged — the only new thing is that the rules now hang off a listener instead of applying inside the mesh.

The playground gives you a single-node `kind` cluster with **Istio 1.30.5** installed with Helm, and **Bookinfo** in the namespace **`bookinfo`**:

- The ingress gateway runs in the namespace **`istio-ingress`**. Its Deployment and Service are both called `istio-ingress`, and its pods carry the label **`istio=ingress`**.
- `bookinfo` holds `productpage`, `details`, `reviews` v1/v2/v3 and `ratings` on port 9080, plus `httpbin` on port 8000 and a `curl` client pod. The `reviews` subsets `v1`, `v2` and `v3` already exist.
- Access logs are on, so the gateway writes one line per request.
- No `Gateway` and no `VirtualService` exist yet.

You need `istioctl` 1.30.5 on your own machine for the `istioctl` commands.

A `kind` cluster has no cloud load balancer, so nothing outside can reach the gateway on its own. `astrona run` keeps a port forward running from `127.0.0.1:8080` to the gateway's port 80, so you do not start one yourself. Check it with `astrona port-forward list`. On a real cloud cluster you would read the address from `status.loadBalancer.ingress[0].ip` instead. The Istio objects are the same either way.

Paste this helper into each new terminal. Every "Try it" in this module uses it. It prints the status code for a path, sent through the gateway with a `Host` header (default `bookinfo.example.com`):

```sh
gateway_status() { curl -s -o /dev/null -w "%{http_code}\n" -H "Host: ${2:-bookinfo.example.com}" "http://localhost:8080$1"; }
```

The graded lab for this module runs in its own cluster with its own workloads. Its `question.md` lists them.

## Where this fits

This is the first of three ways to get north-south traffic into the mesh, and the other two in this section are best understood by contrast with it. The Kubernetes `Ingress` API (module 2) is the compatibility path for manifests that already exist, and the Kubernetes Gateway API (module 3) is the portable successor. All three let outside traffic into the mesh. What differs is the API you write and what it can express.
