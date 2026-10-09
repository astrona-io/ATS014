# Route External Traffic Through An Egress Gateway

When a pod in the mesh sends a request to a host outside the cluster, its own sidecar proxy sends the request straight out. A **sidecar proxy** is the Envoy container that Istio adds to each pod; all traffic in and out of the pod passes through it. This direct path works, and for many clusters it is the right choice. But it means outbound requests leave from every node, the record of them is spread over every sidecar's access log, and an outside partner that wants to allow your address has no single address to allow.

An **egress gateway** puts all of that in one place. It is an Envoy proxy that outbound traffic to outside hosts can be sent through, so the traffic leaves the mesh at one point. It runs the same software as the ingress gateway, used for the other direction. The sidecars send outbound requests to it, and it opens the connection to the outside host. You get one exit, one access log and one source address.

The most important fact to learn before any YAML is this: an egress gateway **receives no traffic by itself**. A request reaches it only because a `VirtualService` with two stages sends it there.

## Learning objectives

After this module you can:

- Explain why a running egress gateway carries no traffic until routing sends traffic to it.
- Write a `Gateway` for the egress gateway, with the **outside** host name in `servers[].hosts`.
- Explain the subset with no labels in the `DestinationRule` for the egress gateway's own Service.
- Write the two-stage `VirtualService`, and say which proxy runs each stage.
- Explain what the reserved gateway name `mesh` means, and why the top-level `gateways` list must name it.
- Send HTTPS through the gateway without decrypting it, with `tls.mode: PASSTHROUGH` and `tls` rules that match on `sniHosts`.
- Prove that a request passed through the egress gateway, from both access logs and from `istioctl proxy-config`.
- Limit which workloads use the egress gateway with `sourceLabels`, and say what that does and does not stop.
- State what the egress gateway gives you and what it costs.

## Before you start

This module expects some knowledge of the mesh, and a playground that is running before the first hands-on step.

### What you should already know

- **How the mesh works.** A sidecar proxy runs next to every pod, and `istiod`, Istio's control plane, sends it its configuration. You can read that configuration with `istioctl proxy-config`.
- **The `ServiceEntry`.** It adds a host outside the mesh to the service registry, the list of hosts that `istiod` knows about, so the mesh can route to it.
- **The `Gateway` and `VirtualService` pair.** A `Gateway` opens a port on a gateway's pods, and a `VirtualService` that names the `Gateway` routes what arrives there.

### What is in your playground

Your playground is one `kind` cluster with **Istio 1.30.5** installed with Helm. Next to `istio-base` and `istiod`, it runs an egress gateway:

| What | Where |
| --- | --- |
| Helm release and namespace | `istio-egress` in the namespace `istio-egress` |
| Deployment and Service | `istio-egress`, Service type `ClusterIP`, ports `80` and `443` |
| Pod label a `Gateway` selects | `istio: egress` |

The egress gateway is running and carries **no** traffic. The mesh uses its default `outboundTrafficPolicy`, `ALLOW_ANY`, so pods may send requests to any outside host. The namespace **`starfleet`** has sidecar injection on and holds one workload:

| Workload | What it does |
| --- | --- |
| `shuttle` | Test client pod in the mesh. You send every test request from here with `curl` |

The `shuttle` pod shows `2/2`: the application container plus its sidecar proxy. Access logs are on for the whole mesh, so the `shuttle` sidecar **and** the egress gateway each write one line per request into their access log. There is no `ServiceEntry`, `Gateway`, `DestinationRule` or `VirtualService` yet.

This module needs outbound internet access. The commands call `https://httpbin.org` from inside the cluster, and without internet access you see network failures, not mesh decisions. Run a plain `curl https://httpbin.org/get` on your own machine first. The graded labs do **not** need internet access.

Start your playground now, and keep it running while you read the parts:

<!-- astrona:playground -->

### Three helpers to paste first

Paste these into each new terminal. `call_external` sends one request from `shuttle` (by default to `https://httpbin.org/get`) and prints the status code, the time and the exit code of `curl`. `log_shuttle` and `log_gate` print the newest line of the `shuttle` sidecar's access log and of the egress gateway's access log.

```sh
call_external() { kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" --max-time 10 "${1:-https://httpbin.org/get}"; echo "  exit=$?"; }
log_shuttle() { sleep 2; kubectl logs -n starfleet deploy/shuttle -c istio-proxy --tail=1; }
log_gate() { sleep 2; kubectl logs -n istio-egress deploy/istio-egress --tail=1; }
```

The log helpers wait two seconds first. For an encrypted connection, the proxy writes its line when the connection closes, which can take a moment. A status of `000` with exit code `35` means the connection was closed before any response came back.

## The order of the parts

The module has six parts, a lab after the fifth part, a lab after the sixth part, and a summary at the end.

The first part shows that a running egress gateway carries no traffic, and why outbound traffic is different from inbound traffic. The second part writes the `Gateway` and the `DestinationRule` for the egress gateway, and explains why each one looks the way it does. The third part writes the two-stage `VirtualService` and follows one request through both proxies.

The fourth part shows how to prove the extra hop from the access logs, and breaks the `VirtualService` in two ways. The fifth part breaks the `Gateway` and the `DestinationRule`, so you can tell each of the four failures by its access log. Its lab asks you to find and fix a route that skips the egress gateway. The sixth part limits the route to labelled workloads with `sourceLabels` and weighs what the egress gateway gives and costs. Its lab asks you to build the route for one workload over plain HTTP.
