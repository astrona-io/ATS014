# Apply And Remove Traffic Rules Safely

A correct `VirtualService` or `DestinationRule` is only half the job. The other half is changing a running mesh without breaking requests while the change happens. Istio objects point at each other: a `VirtualService` points at subsets in a `DestinationRule` and at a `Gateway`, and a route can point at an outside host that a `ServiceEntry` adds. If a pointer reaches a proxy before the object it points at, requests fail, even though every object is correct.

`istiod`, Istio's control plane, does not reach every sidecar proxy at the same moment. For a short time, some proxies have the new configuration and some still have the old one. This module teaches the order of changes that keeps requests working during that gap, and the default behaviour Istio has before you write any rule.

## Learning objectives

After this module you can:

- Name the order to create `ServiceEntry`, `DestinationRule`, `Gateway` and `VirtualService`, and the reverse order to remove them.
- Explain "make before break", and reproduce the `503 NC` that the wrong order causes.
- Check with `istioctl proxy-config clusters` that the client's proxy has a new subset before you test.
- Explain why two files with the same `metadata.name` describe one object, and why to avoid two objects for one host.
- State Istio's defaults for HTTP timeout, retries, load balancing, unknown outside hosts and circuit breaking, and prove two of them.

## Before you start

This module expects some knowledge of Istio routing, and a playground that is ready before the first hands-on step.

### What you should already know

- **Subsets and routes.** A `DestinationRule` defines subsets, which are named groups of pods selected by pod labels. A `VirtualService` route sends requests to one of those subsets.
- **The two `503` flags.** In the access log, `NC` ("no cluster") means the route names a subset that the proxy has no cluster for. `UH` ("no healthy upstream") means the cluster has no healthy pods.
- **Kubernetes basics.** Namespaces, Deployments, Services, pod labels and `kubectl exec`.

The other objects named here (`Gateway`, `ServiceEntry`, `Sidecar`) only need to be names for now. What matters in this module is what they point at.

### What is in your playground

Your playground is one `kind` cluster with **Istio 1.30.5** installed with Helm. Access logs are switched on for every proxy, so each sidecar proxy writes one line per request. All workloads run in the namespace **`starfleet`**, which has sidecar injection switched on:

| Workload | What it does |
| --- | --- |
| `bridge`, `cargo`, `navcom` | The web frontend and two backends of the Istio Bookinfo sample, with other names |
| `scout` v1, v2, v3 | One backend in three versions: v1 returns no stars, v2 black stars, v3 red stars |
| `shuttle` | Test client pod; you send every test request from here |
| `probe` v1, v2 | HTTP echo server on Service port `8000`; paths like `/delay/3` and `/status/503` make the defaults easy to see |

There is **no** `DestinationRule` and **no** `VirtualService` yet. You apply them in the order this module teaches.

The URL paths did not change with the names. The pods run the official Bookinfo images, which answer on fixed paths, so a request to `scout` goes to `http://scout:9080/reviews/0`.

Start your playground now, and keep it running while you read the parts:

<!-- astrona:playground -->

## The order of the parts

The module has two parts, a lab after the first part, and a summary at the end.

The first part shows which proxy reads the `VirtualService` and the `DestinationRule`, the order to apply Istio objects in, and the reverse order to remove them. You reproduce the `503 NC` that the wrong order causes and learn three checks to run before you test. Its lab asks you to retire one version of `scout` while a client sends requests the whole time, without a single failed request.

The second part shows how `kubectl apply` treats two files with the same name, why one host should have one object of each kind, and what Istio does when you have written no rule at all. It ends with a short reference of the response flags in the access log.
