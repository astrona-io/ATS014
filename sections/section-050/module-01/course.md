# Fault Injection With Delays And Aborts

A timeout that you have never seen fire is only a guess. A retry policy that you have never seen retry is a guess too. You could wait for a real outage to find out whether they work. You could also add failure switches to your application code, but then test code runs in production.

**Fault injection** gives you a third way. It is an Istio feature that makes the sidecar proxy fake a failure on purpose. The **sidecar proxy** is the Envoy container that Istio adds to each pod; all traffic in and out of the pod passes through it. You write the fault as a few lines in a **`VirtualService`**, the Istio object that holds the routing rules for requests to a host. The proxy then holds a request back for two seconds, or answers it with an error without sending it on.

The applications do not change at all, and they cannot tell an injected fault from a real one. That is what makes the result worth trusting. Because the fault lives in a routing rule, you also decide exactly which requests it touches, so a test never turns into an outage for everyone.

## Learning objectives

After this module you can:

- Add a `fault.delay` and a `fault.abort` to a `VirtualService` rule, and say exactly what the client gets for each.
- Name the `VirtualService` a fault belongs on, and the sidecar proxy that applies it.
- Explain why an aborted request leaves no trace at the destination, and recognise injected faults by the `DI` and `FI` flags in the client's access log.
- Apply a fault to a share of the requests with `percentage`, to your own test requests with a header `match`, and to one calling workload with `sourceLabels`.
- Use a delay to make a timeout fire on demand, and explain why a rule with a `fault` ignores its own `timeout` and `retries`.
- Find a forgotten fault in the route configuration of a proxy.

## Before you start

This module expects some knowledge of Istio routing, a playground that is ready before the first hands-on step, and two small helper functions in your terminal.

### What you should already know

- **How the mesh works.** A sidecar proxy runs next to every application container, and `istiod`, the Istio control plane, sends configuration to every proxy. You can read that configuration with `istioctl proxy-config`.
- **Routing.** How to write a `VirtualService` with `http` rules and a `match`. A fault is one extra field on a rule you already know how to write.
- **Timeouts and retries.** What a route `timeout` and a `retries` block do. Fault injection is most useful when there is a timeout or retry policy to test.

### What is in your playground

Your playground is one `kind` cluster with **Istio 1.30.5** installed with Helm. Access logs are switched on for the whole mesh. An **access log** is the log where each sidecar proxy writes one line for every request it handles. Everything runs in the namespace **`starfleet`**, which has sidecar injection switched on:

| Workload | What it does |
| --- | --- |
| `bridge`, `cargo` | `bridge` is the web frontend (`/productpage`); it calls `cargo` and `scout`. `cargo` is a backend that returns item details |
| `scout` v1, v2, v3 | A backend in three versions. Only v2 and v3 call `navcom` for a star rating, so a fault on `navcom` shows up through them |
| `navcom` | The backend that `scout` v2 and v3 call for the star rating |
| `probe` v1, v2 | An HTTP echo server on Service port `8000` |
| `shuttle` | The test client pod. You send every test request from here |

A **`DestinationRule`** for `scout` (subsets v1, v2, v3) and one for `navcom` (subset v1) are already applied. A **subset** is a named group of pods of one Service, selected by a label such as `version: v1`. There is **no** `VirtualService` yet, so no fault is injected. You write them in this module.

The `scout` application copies the `end-user` header of the request it receives onto its own request to `navcom`. This is called header propagation. It is what lets a fault on `navcom` hit only one user's requests, even when they pass through `scout`.

Start your playground now, and keep it running while you read the parts:

<!-- astrona:playground -->

### Two helper functions

Paste these into each new terminal before you start:

```sh
status_and_time() { kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" "$@"; }
count_navcom_status() { for i in $(seq 1 10); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" http://navcom:9080/ratings/0
done | sort | uniq -c; }
```

`status_and_time` sends one request from the `shuttle` pod and prints the HTTP status code and the time the request took. Add `-H "end-user: jason"` before the address to send the request as the user `jason`. `count_navcom_status` sends 10 requests from the `shuttle` pod straight to `navcom` and counts the status codes, so you can see a fault that hits only a share of the requests.

## The order of the parts

The module has four parts, a lab after each of the last three parts, and a summary at the end.

The first part injects a delay with `fault.delay`. It shows which `VirtualService` holds the fault, which sidecar proxy applies it, and how to prove the delay from the access logs. The second part injects an abort with `fault.abort`, shows why the destination never sees an aborted request, and combines a delay and an abort on one rule. Its lab asks you to set up one delay and one abort and prove both.

The third part scopes a fault with a `match`: to requests that carry a header, or to requests from one calling workload. Its lab gives you a fault that breaks every request and asks you to limit it to test requests. The fourth part uses faults to test timeouts and retries, shows the rule that ignores its own `timeout` and `retries`, and finds a forgotten fault in the proxy configuration. Its lab asks you to scope a delay and an abort to one test user and make a timeout fire.
