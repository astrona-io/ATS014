# Route External Traffic Through An Egress Gateway

Astronaut, when a ship signals a planet in another solar system, its own communications officer (the sidecar) sends the signal straight out. That works, and for many clusters it is the right answer. But it also means outgoing signals leave from every node, the record of them is spread across every ship's flight log, and a partner planet that wants to allow your address has no single address to allow.

An **egress gateway** pulls all of that into one place. Think of it as the solar system's **departure gate**: one checked exit that every outgoing signal can be sent through. It is the same program as the ingress gateway, pointed the other way. Ships send their outgoing signals to it, and it makes the connection to the outside world. One exit, one flight log, one source address.

The single most important thing to understand before any YAML:

> An egress gateway **catches nothing by itself**. A signal reaches it only because a flight plan, a `VirtualService` with two stages, sends it there.

## Learning objectives

After this module you can:

- Explain why a running egress gateway carries no traffic until routing sends it there.
- Write a `Gateway` for the egress gateway, with the **external** host name in `servers[].hosts`.
- Explain the empty subset in the `DestinationRule` for the gateway's own Service.
- Write the two-stage `VirtualService`, and say which proxy runs each stage.
- Explain what the reserved gateway name `mesh` means, and why the top-level `gateways` list must name it.
- Route HTTPS through the gateway unopened, with `tls.mode: PASSTHROUGH` and `tls` rules on `sniHosts`.
- Prove a signal flew through the gate, from both flight logs and from `istioctl proxy-config`.
- Limit which ships use the gate with `sourceLabels`, and say what that does and does not stop.
- State what the gate gives you and what it costs.

## Before you start

Every mission starts with a pre-flight check, astronaut. Check what you should already know, see what waits in your playground, and paste three helpers into your terminal.

### What you should already know

- **How the mesh works.** A proxy (the communications officer) sits beside every pod, and `istiod` (mission control) sends it orders. You can read those orders with `istioctl proxy-config`.
- **The `ServiceEntry`.** It adds a planet from another solar system to the star chart, so the mesh can route to it.
- **The `Gateway` and `VirtualService` pair.** A `Gateway` opens a port on a gateway's pods, and a `VirtualService` that names the `Gateway` routes what arrives there.

### What is in your playground

Your playground is a small training solar system: one `kind` cluster with **Istio 1.30.5** installed with Helm. Next to `istio-base` and `istiod`, it runs an **egress gateway**:

| What | Where |
| --- | --- |
| Helm release and namespace | `istio-egress` in the namespace `istio-egress` |
| Deployment and Service | `istio-egress`, Service type `ClusterIP`, ports `80` and `443` |
| Pod label a `Gateway` selects | `istio: egress` |

The gateway is running and carries **no** traffic. The mesh is at its default, `ALLOW_ANY`, so ships may signal any planet. Your ship lives on the planet **`starfleet`**:

| Ship | Its role |
| --- | --- |
| `shuttle` | **Your shuttle**. You send every test signal from here, with the `curl` command |

The shuttle shows `2/2`: the app plus its communications officer. Mesh-wide access logs are on, so the shuttle's sidecar **and** the egress gateway each write one line per signal into their flight log. There is no `ServiceEntry`, `Gateway`, `DestinationRule` or `VirtualService` yet.

> [!WARNING]
> **This module needs outbound internet access.** The commands call `https://httpbin.org` from inside the cluster. Without internet access you see network failures, not mesh decisions. Run a plain `curl https://httpbin.org/get` on your own machine first. The graded missions do **not** need internet access.

Launch your playground now, and keep it running next to you while you read the parts:

<!-- astrona:playground -->

### Three helpers to paste first

Paste these into each new terminal. The first sends one signal from the shuttle (by default to `https://httpbin.org/get`) and prints the status code, the time, and the exit code of `curl`. The other two print the newest line of each flight log: the shuttle's sidecar, and the egress gateway.

```sh
call_external() { kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" --max-time 10 "${1:-https://httpbin.org/get}"; echo "  exit=$?"; }
log_shuttle() { sleep 2; kubectl logs -n starfleet deploy/shuttle -c istio-proxy --tail=1; }
log_gate() { sleep 2; kubectl logs -n istio-egress deploy/istio-egress --tail=1; }
```

The log helpers wait two seconds first. For an encrypted signal, the proxy writes its line when the connection closes, which can take a moment. A result of `000` with exit `35` means the connection was cut before any answer came back.

## Why this matters

Most applications depend on something outside the cluster. Sending all of it through one departure gate gives you one place to watch, one address to allow, and one place to put policy. It also gives you a new way to be wrong: a gate that is deployed, looks healthy, and that no signal ever uses. This module trains you to tell the two apart.
