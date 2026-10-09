# Route Requests Within The Mesh

A plain Kubernetes Service cannot choose which version of an application gets a request. The `scout` Service selects three versions, v1, v2 and v3, and `kube-proxy` sends each connection to any of them. It cannot read a header or a path, so it cannot send some requests to v2 while the rest stay on v1.

Istio moves that choice into the sidecar proxy (Envoy) of the client pod, which can read the request. Two Istio objects configure it. A **`VirtualService`** decides **where** a request goes. A **`DestinationRule`** defines **what the named destinations are**, such as a subset of pods with the label `version: v2`.

This module spends twelve parts on these two objects, because most traffic management features are one more field on one of them. Weighted routing, mirroring, timeouts, retries and fault injection are fields on a `VirtualService` rule. Connection pools, load balancing and outlier detection are fields on a `DestinationRule`.

## Learning objectives

After this module you can:

- Explain the split of work between `VirtualService` and `DestinationRule`, and name which one creates subsets and which one uses them.
- Define subsets over pod labels, and predict what happens when a subset's labels match no pod.
- Send all traffic of a service to one subset, and switch it to another without touching the pods.
- Write `match` rules on `headers`, `uri`, `queryParams` and `method`, choosing correctly between `exact`, `prefix` and `regex`.
- State whether two match conditions are combined with AND or OR from their position in the YAML.
- Predict which `http` rule wins for a given request, and place a catch-all route correctly.
- Fill in a short host name to the namespace Istio will actually use.
- Use `redirect`, `rewrite`, `headers` and `corsPolicy` on a matched rule, and say which of them ends the request.
- Explain how a Service port's name or `appProtocol` decides the protocol, and diagnose a port declared as the wrong one.
- Tell `404 NR`, `503 NC` and `503 UH` apart from the access log, and say what each one means you should fix.

## Before you start

This module expects some knowledge, and a playground that is ready before the first hands-on step.

### What you should already know

- **How the mesh works.** A sidecar proxy runs in every pod, and `istiod`, Istio's control plane, sends it configuration. You can read that configuration with `istioctl proxy-config`.
- **Kubernetes basics.** Namespaces, Deployments, Services, pod labels and `kubectl exec`.

### What is in your playground

Your playground is one `kind` cluster with **Istio 1.30.5** already installed. Everything you need is in the namespace **`starfleet`**, which has sidecar injection switched on. It runs the Istio Bookinfo sample app with other names:

| Workload | What it does |
| --- | --- |
| `bridge` | Web frontend (`/productpage`) on port `9080`; it calls `cargo` and `scout` |
| `cargo` | Backend that returns item details |
| `scout` v1, v2, v3 | Backend in three versions behind one Service: v1 shows no stars, v2 black stars, v3 red stars |
| `navcom` | Backend that `scout` v2 and v3 call for the star rating |
| `shuttle` | Test client pod; you send test requests from here with `curl` |
| `probe` v1, v2 | HTTP echo server on Service port `8000`; it returns what it receives |

Every pod shows `2/2`: the application container plus the `istio-proxy` sidecar. There is **no** `VirtualService` and **no** `DestinationRule` yet.

The URL paths inside the images keep their original names. A request to `scout` goes to `http://scout:9080/reviews/0`, and the `bridge` page is at `/productpage`.

You can also open the `bridge` page in your browser at `http://127.0.0.1:9080/productpage`. Log in as `jason` (any password works). From then on, every request that `bridge` sends to `scout` carries the header `end-user: jason`.

Start your playground now, and keep it running while you read the parts:

<!-- astrona:playground -->

### One helper to paste first

Paste this into each new terminal before you start. It sends 10 requests from `shuttle` to `scout` and counts which version answered:

```sh
count_versions() { for i in $(seq 1 10); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s "$@" | grep -o 'scout-v[0-9]' || echo none
done | sort | uniq -c; }
SCOUT=http://scout:9080/reviews
```

Use it like this: `count_versions $SCOUT/0`. Any `curl` options you add, such as `-H "end-user: jason"`, are passed on.

## The order of the parts

The module has twelve parts, five labs placed right after the parts they practise, and a summary at the end.

The first part shows where requests go with no routing rules, and that the client's proxy makes the choice. The second part defines subsets with a `DestinationRule` and shows what happens when a subset selects no pod. Its lab asks you to fix a `DestinationRule` subset that selects no pods.

The third part writes the first `VirtualService` and sends requests from `jason` to their own version. The fourth part covers the three ways to compare text: `exact`, `prefix` and `regex`. The fifth part shows when two conditions in a `match` are combined with AND and when with OR. The sixth part proves which one you wrote by reading the proxy's route table. The seventh part puts the rules in order and adds a catch-all. Its lab asks you to route requests by header, URI and query parameter.

The eighth part shows how Istio fills in short host names from the object's namespace. The ninth part reads the access log and the proxy's live configuration, and ends with a debugging checklist. Its lab asks you to fix a `VirtualService` that does not apply.

The tenth part uses `redirect` and `rewrite` on a matched rule. The eleventh part changes request and response headers and answers browser preflight requests with `corsPolicy`. Its lab asks you to redirect, rewrite and change the headers of a request. The twelfth part explains how Istio picks a port's protocol and how `tcp` and `tls` routing work. Its lab asks you to declare a Service port as HTTP.
