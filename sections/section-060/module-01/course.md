# Expose A Service With An Istio Ingress Gateway

Inside the mesh, requests travel from one pod to another, and both ends have a sidecar proxy: an Envoy container that Istio adds to each pod. This is called east-west traffic. This module is about north-south traffic: requests that come from outside the cluster, for example from a browser or another system. The client has no sidecar proxy and is not part of the mesh.

These requests enter through the ingress gateway: an Envoy proxy at the edge of the mesh that accepts traffic from outside the cluster. It runs in its own pod, with no application next to it, behind a Kubernetes Service. You configure it with two Istio objects. A `Gateway` opens a listener on the gateway pods, and a `VirtualService` bound to that `Gateway` says where each request goes next.

## Learning objectives

After this module you can:

- Explain what the ingress gateway pod is, where it runs, and how it differs from a sidecar proxy.
- Write a `Gateway` that opens an HTTP listener for named hosts, and find the right `selector` labels for your install.
- Bind a `VirtualService` to that listener with `gateways:`, and explain what the reserved value `mesh` means.
- Predict what a host mismatch between the two objects does.
- Refer to a `Gateway` in another namespace correctly.
- Tell an empty response (`000`), a `404 NR` and a `503 NC` apart, and know which object each one points at.
- Read the gateway's own listeners, routes and endpoints with `istioctl proxy-config`.

## Before you start

This module expects some knowledge of Istio routing, and a playground that is ready before the first hands-on step.

### What you should already know

- **How the mesh works.** A sidecar proxy runs next to every application container, and `istiod`, Istio's control plane, sends it configuration. You can read that configuration with `istioctl proxy-config`.
- **How a `VirtualService` routes.** A `VirtualService` holds an ordered list of `http` rules, each with an optional `match` and a `route`. The first rule that matches a request wins.
- **Kubernetes basics.** Namespaces, Deployments, Services, pod labels and `kubectl logs`.

### What is in your playground

Your playground is one `kind` cluster with **Istio 1.30.5**, installed with Helm, plus an ingress gateway. The sample application runs in the namespace **`starfleet`**:

| Workload | What it does |
| --- | --- |
| `bridge` | Web frontend (`/productpage`) on port `9080`. This is the Service you expose to the outside |
| `cargo`, `navcom` | Backends that `bridge` and `scout` call |
| `scout` v1, v2, v3 | Backend in three versions. Its subsets `v1`, `v2` and `v3` already exist |
| `probe` v1, v2 | HTTP echo server on port `8000`; it returns what it receives |
| `shuttle` | Test client pod inside the mesh |

The ingress gateway runs in its own namespace, **`istio-ingress`**. Its Deployment and its Service are both called `istio-ingress`, and its pod carries the label **`istio=ingress`**. Access logs are on, so the gateway writes one line for every request. No `Gateway` and no `VirtualService` exist yet: you write them in this module.

The workloads are the Istio Bookinfo sample with other names. The paths built into the images keep their original names, so `bridge` answers on `/productpage`.

A `kind` cluster has no cloud load balancer, so nothing outside the cluster can reach the gateway on its own. `astrona run` keeps a port forward running from `127.0.0.1:8080` to the gateway's port `80`. Check it with `astrona port-forward list`. On a cloud cluster you would read the address from `status.loadBalancer.ingress[0].ip` instead; the Istio objects are the same either way. You also need `istioctl` 1.30.5 on your own machine.

Start your playground now, and keep it running while you read the parts:

<!-- astrona:playground -->

### One helper to paste first

Paste this into each new terminal. It sends one request through the gateway for a path, with a `Host` header (`starfleet.example.com` unless you name another host), and prints only the status code:

```sh
gateway_status() { curl -s -o /dev/null -w "%{http_code}\n" -H "Host: ${2:-starfleet.example.com}" "http://localhost:8080$1"; }
```

Use it like this: `gateway_status /productpage`, or `gateway_status /productpage other.example.com`.

## The order of the parts

The module has four parts, a lab after the first, third and fourth parts, and a summary at the end.

The first part shows the gateway pod and its Service, and opens a listener with a `Gateway`, first with a wrong selector and then with the right one. Its lab asks you to fix a `Gateway` whose selector matches no pod. The second part binds a `VirtualService` to the `Gateway` with the `gateways:` field, and shows what happens when that field is missing.

The third part lines up the hosts of the two objects, uses a subset behind the gateway, and refers to a `Gateway` by namespace. Its lab asks you to expose two hosts through one gateway. The fourth part tells `000`, `404` and `503` apart and gives an order of checks for any gateway. Its lab asks you to repair a gateway configuration with several faults.
