# Expose A Service With An Istio Ingress Gateway

Astronaut, so far every signal you steered was **east-west** traffic: one spaceship in the mesh signalling another, inside your own solar system (the cluster). Both ends of every call had a communications officer (the sidecar proxy) on board. This mission is about **north-south** traffic: signals that arrive from outside the solar system, from a browser or another system. The sender has no communications officer, and it is not part of the mesh.

Those signals come in through the **ingress gateway**: the spaceport arrival gate, the one door that signals from outside come through. It is the same Envoy program that runs as every sidecar, but it stands on its own, with no app beside it, and a Kubernetes Service puts it in front of the outside world. You set it up with two objects: a `Gateway` opens the gate, and a `VirtualService` (the flight plan) linked to it says where each arriving signal flies next.

## Learning objectives

After this module you can:

- Explain what the ingress gateway pod is, where it runs, and how it differs from a sidecar.
- Write a `Gateway` that opens an HTTP listener for named hosts, and find the right `selector` labels for your install.
- Link a `VirtualService` to that listener with `gateways:`, and explain what the reserved value `mesh` means.
- Predict what a host mismatch between the two objects does.
- Reference a `Gateway` in another namespace correctly.
- Tell an empty reply (`000`), a `404 NR` and a `503 NC` apart, and know which part of the setup each one points at.
- Read the gateway's own listeners, routes and endpoints with `istioctl proxy-config`.

## Before you start

Every mission starts with a pre-flight check. Make sure you have the knowledge this module expects, know what is waiting in your playground, and have one small helper ready in your terminal.

### What you should already know

- **How the mesh works.** A proxy sits beside every pod, and `istiod` (mission control) sends it orders. You can read those orders with `istioctl proxy-config`.
- **The flight plan.** A `VirtualService` holds an ordered list of `http` rules, each with an optional `match` and a `route`. The first rule that fits a signal wins.
- **Kubernetes basics.** Namespaces, Deployments, Services, pod labels and `kubectl logs`.

### What is in your playground

Your playground is a small training solar system: one `kind` cluster with **Istio 1.30.5**, installed with Helm, plus an ingress gateway. The fleet lives on the planet (namespace) **`starfleet`**:

| Ship | Its role in the fleet |
| --- | --- |
| `bridge` | The **flagship**: the web page astronauts see, on port `9080`. It is the ship you expose to the outside |
| `cargo`, `navcom` | The supply ship and the navigation computer the bridge and the scouts ask |
| `scout` v1, v2, v3 | Three **ship classes** of one scout. Its subsets `v1`, `v2` and `v3` already exist |
| `probe` v1, v2 | An **echo probe** on port `8000` that sends back what it receives |
| `shuttle` | Your client inside the mesh |

The ingress gateway lives on its own planet, **`istio-ingress`**. Its Deployment and its Service are both called `istio-ingress`, and its pod carries the label **`istio=ingress`**. Flight logs (access logs) are on, so the gateway writes one line for every signal. No `Gateway` and no `VirtualService` exist yet: writing them is your mission.

The Starfleet is the Istio docs' Bookinfo sample with space names. The paths built into the ships keep their old names, so the bridge answers on `/productpage`.

A `kind` cluster has no cloud load balancer, so nothing outside can reach the gateway on its own. `astrona run` keeps a port forward running from `127.0.0.1:8080` to the gateway's port `80`. Check it with `astrona port-forward list`. On a real cloud cluster you would read the address from `status.loadBalancer.ingress[0].ip` instead; the Istio objects are the same either way. You also need `istioctl` 1.30.5 on your own machine.

Launch your playground now, and keep it running next to you while you read the parts:

<!-- astrona:playground -->

### One helper to paste first

Paste this into each new terminal. It sends one signal through the gateway for a path, with a `Host` header (`starfleet.example.com` unless you name another host), and prints only the status code:

```sh
gateway_status() { curl -s -o /dev/null -w "%{http_code}\n" -H "Host: ${2:-starfleet.example.com}" "http://localhost:8080$1"; }
```

Use it like this: `gateway_status /productpage`, or `gateway_status /productpage other.example.com`.

## Why this matters

Every service your users reach from outside enters the mesh through a gate like this one. The same two objects, a `Gateway` and a linked `VirtualService`, decide which hosts and paths come in, and everything you already know about flight plans works behind the gate unchanged. Most gateway failures come down to one missing line or one mismatched label, and they all show up as the same few status codes, so learning to read those codes saves you hours.
