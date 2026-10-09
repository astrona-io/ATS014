# Circuit Breaking With Connection Pool Limits

A timeout protects one request. A **circuit breaker** protects a client while the service it calls is slow or overloaded. It is a limit in the sidecar proxy (Envoy) that refuses new requests at once when too much work to one service is already open. The sidecar proxy is the proxy container that Istio adds to each pod; all traffic in and out of the pod passes through it.

Without such a limit, requests pile up while they wait for a slow service. Memory and worker threads fill up with work that will probably fail anyway. The client gets slow too, and the services that call the client start to suffer. Nothing crashed, yet a whole chain of services stops working.

Istio's answer is a limit on open work. You cap how many connections and waiting requests one client may have open to one service at the same time. The proxy refuses anything above that cap **at once**, with the HTTP status `503` (Service Unavailable). A fast refusal is better than a slow failure.

## Learning objectives

After this module you can:

- Configure `trafficPolicy.connectionPool` in a `DestinationRule` with TCP and HTTP limits, and name what each setting caps.
- Explain why a limit on requests at the same time is not a limit on requests in total, and design a test that really trips it.
- Explain why `http1MaxPendingRequests` decides whether an HTTP/1 circuit breaker trips at all.
- Identify a circuit-breaker refusal by the `UO` response flag and the `upstream_rq_pending_overflow` counter.
- Read the live limits out of a proxy with `istioctl proxy-config cluster`, on the client side and on the server side.
- Explain why a client proxy's own refusals are never retried, and how retries still multiply the load on a failing service.

## Before you start

This module builds on basic Istio traffic management. It expects the following knowledge, and a playground that is ready before the first hands-on step.

### What you should already know

- **How the mesh works.** A sidecar proxy runs next to the application in every pod, and `istiod`, the Istio control plane, sends it its configuration. You can read that configuration with `istioctl proxy-config`.
- **`DestinationRule` and `trafficPolicy`.** A `DestinationRule` sets how a client proxy sends traffic to one service. This module uses its `trafficPolicy` field, with new keys inside.
- **A retry policy on a `VirtualService`.** The last part uses `retries` with `attempts` and `retryOn`.

### What is in your playground

Your playground is one `kind` cluster with **Istio 1.30.5** installed with Helm. Access logs are switched on for every sidecar proxy, so each proxy writes one line per request. Everything runs in the namespace **`starfleet`**, which has sidecar injection switched on:

| Workload | What it does |
| --- | --- |
| `probe` v1 and v2 | HTTP echo server: two pods behind one Service on port `8000`. It is the service you put connection pool limits on |
| `fortio` | Load generator: it sends many requests **at the same time**. Its pod has two containers, `fortio` and `istio-proxy`, so some commands pick one with `-c` |
| `shuttle` | Test client pod: it sends single requests with `curl`, one at a time |

This module is all about requests at the same time. A `curl` loop only sends one request at a time, so `fortio` is the main tool here. Its sidecar proxy is also set up to keep the circuit-breaker counters that the parts read.

There is **no `DestinationRule`** yet, so there is no limit at all.

Start your playground now, and keep it running while you read the parts:

<!-- astrona:playground -->

## The order of the parts

The module has three parts, a lab after the second part, a lab after the third part, and a summary at the end.

The first part shows the connection pool settings and the queue model behind them. It proves that the limits count requests at the same time, and that `http1MaxPendingRequests` decides whether anything is refused. The second part shows how to prove that a `503` came from the circuit breaker: the `UO` flag in the access log and the overflow counters in the proxy. Its lab asks you to configure a connection pool and prove that it refuses requests sent at the same time.

The third part reads the limits out of the client proxy and the server proxy, shows who each limit protects, and shows how retries interact with the circuit breaker. Its lab asks you to fix a retry policy that sends every failing request to a struggling service again and again.
