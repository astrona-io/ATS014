# Compose And Scope VirtualServices With delegate And exportTo

A `VirtualService` is the Istio object that sets how requests to a host are routed. In a small mesh one object per host is enough. In a larger mesh, two problems appear. Several teams want to own different parts of the routes for one host, and an object in one namespace can change how clients in every other namespace behave.

Istio has fields for both. A root `VirtualService` can hand part of its route table to other `VirtualService` objects with `delegate`. The `exportTo` field limits which namespaces receive a `VirtualService` or a `DestinationRule`. And `sourceLabels`, `sourceNamespace` and `port` inside a `match` make a rule depend on who sends the request and on which port it uses.

## Learning objectives

After this module you can:

- Write a root `VirtualService` that sends a path prefix to a delegate `VirtualService`, and explain why the delegate has no `hosts`.
- Say how the root `match` narrows the delegate's `match`, and name what a delegate cannot do (a second level of delegation, `tcp` or `tls` routes).
- Use `exportTo` with `"."`, `"*"`, `"~"` and a list of namespaces on a `VirtualService` and a `DestinationRule`.
- Prove from a client in a second namespace whether it received an object, with live requests and `istioctl proxy-config`.
- Explain why a `VirtualService` that is visible with a `DestinationRule` that is not visible fails with `503`.
- Match on `sourceLabels`, `sourceNamespace` and `port`, and say what these matches cannot do.

## Before you start

This module expects some knowledge of Istio routing, and a playground that is ready before the first hands-on step.

### What you should already know

- **How a `VirtualService` routes.** A `VirtualService` holds an ordered list of `http` rules, each with an optional `match` and a `route`. The first rule that matches a request wins.
- **Subsets.** A `DestinationRule` defines subsets, which are named groups of a Service's pods selected by pod labels. A route sends requests to one of those subsets.
- **Kubernetes basics.** Namespaces, Deployments, Services, pod labels and `kubectl exec`.

### What is in your playground

Your playground is one `kind` cluster with **Istio 1.30.5**, installed with Helm. Access logs are switched on for every proxy. Two namespaces have sidecar injection switched on: **`starfleet`** and **`dock`**.

| Workload | Namespace | What it does |
| --- | --- | --- |
| `probe` v1, v2 | `starfleet` | HTTP echo server. The Service has port `8000`, and a second port `8001` that reaches the same container. The path `/hostname` returns the name of the pod that answered |
| `shuttle` | `starfleet` | Test client pod; most requests are sent from here |
| `patrol` | `starfleet` | A second test client pod with the pod label `app: patrol` |
| `shuttle` | `dock` | A test client pod in the second namespace |

The `probe` `DestinationRule` with the subsets `v1` and `v2` already exists. No `VirtualService` exists yet: you write them in this module.

Start your playground now, and keep it running while you read the parts:

<!-- astrona:playground -->

### One helper script

The playground ships the helper script `count-versions.sh`. It sends 10 requests from a client pod and prints how many were answered by each `probe` version. A request that gets no pod name back, for example an error, is counted as `status <code>`.

Use it like this: `astrona res run count-versions.sh -- starfleet shuttle http://probe:8000/hostname`. The first two arguments are the client's namespace and Deployment name. Everything after them goes to `curl`.

## The order of the parts

The module has three parts, a lab after each of the first two, and a summary at the end.

The first part splits one route table with a delegate: a root `VirtualService` hands the path `/hostname` and the path `/delay` to two delegate objects. Its lab asks you to build a root and two delegates. The second part limits who receives a `VirtualService` or a `DestinationRule` with `exportTo`, and proves it from a client in the `dock` namespace. Its lab asks you to find why a `VirtualService` has no effect in a second namespace and to fix it. The third part matches on the source workload, the source namespace and the destination port, and says what none of these matches can do.

A capstone lab for the section combines these skills with header and path matching and subsets.
