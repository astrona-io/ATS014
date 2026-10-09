# Control External Access With ServiceEntry

Real applications send requests to hosts outside the cluster: a payment API, an object store, a partner's endpoint, a package registry. Traffic that leaves the cluster like this is called **egress** traffic. This module shows how Istio decides whether such a request may leave, and how you put Istio's routing rules on it.

Istio only knows the hosts in its **service registry**. The service registry is the list of hosts and endpoints that `istiod`, Istio's control plane, knows about: every Kubernetes Service, plus every `ServiceEntry` and `WorkloadEntry` object. A host outside the cluster is not in that list, so Istio cannot route it, time it out or report on it. By default, Istio does not block it either.

Two settings change that. A **`ServiceEntry`** adds a host outside the mesh to the service registry. The **`REGISTRY_ONLY`** outbound traffic policy makes the sidecar proxy refuse every host that is not in the service registry. Once a host is in the registry, a `VirtualService` and a `DestinationRule` work on it exactly as they work on a Service inside the cluster.

## Learning objectives

After this module you can:

- Explain `meshConfig.outboundTrafficPolicy.mode` and the difference between `ALLOW_ANY` and `REGISTRY_ONLY`.
- Block unknown hosts in one namespace with `outboundTrafficPolicy` on a `Sidecar` resource.
- Recognise the response a blocked destination produces, and tell it apart from a network failure.
- Read `PassthroughCluster`, `BlackHoleCluster` and `outbound|443||<host>` in the access log, and say which path a request took.
- Write a `ServiceEntry` for an external host, with the right `location` and `resolution`.
- Explain why the declared `protocol` decides whether HTTP features are available.
- Apply a `VirtualService` timeout and a `DestinationRule` connection pool to an external host.
- Limit a `ServiceEntry` with `exportTo`, and find the cause when a `Sidecar` hides one.

## Before you start

This module builds on the basic Istio objects. It also needs a playground with outbound internet access, and one shell helper.

### What you should already know

- **How the mesh works.** A sidecar proxy (Envoy) runs next to every application container in the mesh, and `istiod` sends it its configuration. You can read that configuration with `istioctl proxy-config`.
- **`VirtualService` and `DestinationRule`.** A `VirtualService` with a `timeout`, and a `DestinationRule` with a `connectionPool`.
- **The `Sidecar` resource.** It limits which hosts the sidecar proxies in one namespace get configuration for, with `egress.hosts`.

### What is in your playground

Your playground is one `kind` cluster with **Istio 1.30.5** installed with Helm (`istio-base` and `istiod` only, no gateways). The mesh uses the default outbound traffic policy, `ALLOW_ANY`. Everything you need runs in the namespace **`starfleet`**, which has sidecar injection switched on:

| Workload | What it does |
| --- | --- |
| `shuttle` | Test client pod. You send every test request from here, with the `curl` command |
| `probe` v1, v2 | HTTP echo server inside the cluster, on Service port `8000`. You use it to compare a request that stays in the cluster with one that leaves |

Every pod shows `2/2`: the application container plus the `istio-proxy` sidecar container. Mesh-wide access logs are on, so every sidecar proxy writes one line per request or connection to its log. There is **no** `ServiceEntry` and **no** `Sidecar` resource yet, so the service registry holds only the Services in the cluster.

> [!WARNING]
> **This module needs outbound internet access.** The commands call real hosts on the internet: `httpbin.org`, `de.wikipedia.org`, `en.wikipedia.org` and `www.google.com`. Without internet access you see network failures, not decisions of the mesh. Run a plain `curl https://httpbin.org/get` on your own machine first. The graded labs do **not** need internet access.

Start your playground now, and keep it running while you read the parts:

<!-- astrona:playground -->

### One helper to paste first

Paste this into each new terminal. It sends one request from the `shuttle` pod and prints the status code, the time, and the exit code of `curl`:

```sh
call_external() { kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" --max-time 10 "$@"; echo "  exit=$?"; }
```

Use it like this: `call_external https://httpbin.org/get`. A result of `000` with exit code `35` or `56` means the connection was closed before any HTTP response came back.

## The order of the parts

The module has four parts, a lab after the third part, a lab after the fourth part, and a summary at the end.

The first part shows the outbound traffic policy: what `ALLOW_ANY` lets through, how `REGISTRY_ONLY` refuses unknown hosts, and how a refusal looks in `curl` and in the access log. The second part takes the `ServiceEntry` apart field by field, and adds `httpbin.org` and a wildcard domain to the service registry.

The third part puts a `VirtualService` timeout and a `DestinationRule` connection pool on an external host, and shows why only a port declared as `HTTP` gets HTTP features. It also explains `exportTo`. Its lab asks you to allow exactly one external endpoint and give it a timeout.

The fourth part shows why a correct `ServiceEntry` can still be refused: its `exportTo` or the caller's `Sidecar` resource hides it from the caller. Its lab asks you to find and fix a `ServiceEntry` that the caller cannot see and that declares the wrong protocol.
