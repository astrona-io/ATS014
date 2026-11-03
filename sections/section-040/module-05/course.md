# Connection Timeouts, Keepalive And Nearby Endpoints

Every request from one pod to another travels over a TCP connection. The sidecar proxy of the calling pod, an Envoy proxy that Istio adds to each pod, opens that connection, keeps it open for later requests, and closes it when it is no longer needed. A request can fail or slow down before any application code runs: the connection attempt can hang, an idle connection can be dropped by a network device, and one long-lived connection can stay on the same endpoint for days.

This module is about those connection settings and about choosing endpoints that are close to the caller. You set them on the calling side, in the `DestinationRule` of the host, which is the Istio object that sets what happens after routing picks a host (connection pool, load balancing, outlier detection and TLS to the upstream). The last part uses a field of the Kubernetes `Service` itself.

## Learning objectives

After this module you can:

- Set `connectionPool.tcp.connectTimeout` and say what the proxy does with a request when the upstream does not accept the connection.
- Tell the connect timeout apart from the route `timeout` of a `VirtualService`, and say which one produces which failure.
- Read the connect timeout of a host from `istioctl proxy-config cluster -o json`.
- Set `connectionPool.http.idleTimeout`, `connectionPool.tcp.maxConnectionDuration` and `connectionPool.tcp.tcpKeepalive`, and say what each one does.
- Find each of these settings in the cluster JSON of the proxy.
- Set `spec.trafficDistribution: PreferClose` on a Kubernetes `Service` and prove that requests from a client stay in its own zone.
- Say what `PreferClose` cannot do, and which `DestinationRule` setting failover still needs.

## Before you start

This module expects some knowledge, a running playground, and two small helper scripts from the playground.

### What you should already know

- **How the mesh works.** A sidecar proxy runs beside every application container. `istiod`, Istio's control plane, sends configuration to every proxy. You can read that configuration with `istioctl proxy-config`.
- **The two objects.** A `VirtualService` sets how requests to a host are routed, with timeouts and retries per route. A `DestinationRule` sets the policy for the host after routing.
- **Kubernetes basics.** Nodes and their labels, Deployments, Services and `kubectl exec`.

### What is in your playground

Your playground is one `kind` cluster with **Istio 1.30.5** already installed. Its single node has the region label `local` and the zone label `zone-a`. All workloads run in the namespace **`starfleet`**, which has sidecar injection switched on:

| Workload | What it does |
| --- | --- |
| `shuttle` | Test client pod. You send every test request from here. It runs in the node's locality, `local/zone-a` |
| `probe-zone-a` | HTTP echo server in locality `local/zone-a`, the same zone as `shuttle` |
| `probe-zone-b` | HTTP echo server in locality `local/zone-b` |
| `probe-zone-a-damaged` | A pod in `local/zone-a` that returns `503` to every request but stays ready. It starts at 0 replicas |

The probe pods sit behind one Service, `probe`, on port `8000`. Its `/hostname` path returns the name of the pod that answered, and `/delay/<seconds>` waits before it answers.

The playground has one node, so the zones are not real. Each probe sets its own locality with the `istio-locality` pod label (format `region.zone`, with a dot), which overrides the locality a pod takes from its node.

There is **no** `DestinationRule`, `VirtualService` or `trafficDistribution` yet. You write them in this module.

Start your playground now, and keep it running while you read the parts:

<!-- astrona:playground -->

### Two helper scripts

`count-zones.sh` sends requests from `shuttle` to the probe and counts which zone answered. `show-connection-settings.sh` prints the connect timeout, idle timeout, maximum connection duration and keepalive settings from the proxy of `shuttle`.

`astrona res run count-zones.sh -- 20` sends 20 requests, and `astrona res run show-connection-settings.sh` prints the settings.

## The order of the parts

The module has three parts and a summary. A graded lab comes after the second and the third part.

The first part is about the connection attempt. It shows how long the proxy waits for an upstream to accept a connection, what the client sees when it does not, and how that differs from the route timeout.

The second part is about the life of a connection that is already open: how long it may stay idle, how long it may live in total, and how TCP keepalive probes check that the other end is still there. Its lab asks you to set all of these on a `DestinationRule` and prove them from the proxy.

The third part is about choosing the endpoint. It shows how the Kubernetes `Service` field `trafficDistribution: PreferClose` keeps requests in the caller's zone, and what it cannot do. Its lab asks you to keep the requests of a client in its own zone.
