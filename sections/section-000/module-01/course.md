# How A Request Moves Through The Mesh

<!-- astrona:playground -->
> [!NOTE]
> 🧪 **Hands-on playground for this module** — a clean, throwaway machine to explore on. No task, no grading. Folder: [`playground/`](https://github.com/astrona-io/ATS014/tree/main/sections/section-000/module-01/playground)
>
> ```sh
> astrona run --git ssh://git@github.com/astrona-io/ATS014.git -c sections/section-000/module-01/playground
> astrona destroy ats-014-playground-000-01
> ```

Every other module in this course writes an object that tells a proxy what to do. This one is about the proxy: where it came from, how traffic ends up going through it, who configures it, and how to ask it what it currently believes.

None of it is configuration you write. It is what already exists the moment a namespace is injected — and it is the difference between following the rest of the course and understanding it. Almost every confusing result in this domain traces back to one of four mix-ups this module settles:

> A **Service** groups pods. **kube-proxy** would pick one at random. **istiod** writes configuration. The **istio-proxy sidecar** is what actually decides, and it decides in the pod that *sent* the request.

If you already know what a sidecar is, what `istiod` pushes, and what `istioctl proxy-config` prints, you can skim this and start at section 010. If any of those is new, this module is the cheapest hour in the course.

## How this module is organised

1. **[The Sidecar And The Data Path](./course-01-the-sidecar-and-the-data-path.md)** — what injection adds to a pod, how `iptables` puts traffic through the proxy without the application knowing, and why every in-mesh request is seen by two proxies.
2. **[How The Proxy Gets Its Configuration](./course-02-how-the-proxy-gets-its-configuration.md)** — `istiod`, the service registry, the four xDS channels, and the listener → route → cluster → endpoint chain that every request walks down.
3. **[The Diagnostic Toolkit](./course-03-the-diagnostic-toolkit.md)** — `analyze`, `proxy-status`, `proxy-config`, `x describe` and access-log response flags, in the order that narrows a problem fastest.

## Learning objectives

After this module you can:

- Explain what sidecar injection adds to a pod, and why a namespace label alone does not change running pods.
- Describe how outbound and inbound traffic reach the proxy without the application being configured for it.
- Name which side of a call enforces routing and which side enforces inbound policy, and say what an uninjected caller loses.
- Expand LDS, RDS, CDS and EDS, and say which one carries a given piece of configuration.
- Trace one request down the listener → route → cluster → endpoint chain and read the output of each layer.
- Decode an Envoy cluster name into direction, port, subset and host.
- Choose the right diagnostic command for a symptom, and state what each one cannot see.
- Read a response flag such as `NR` or `UH` from an access log and say which half of the configuration to inspect.

## Before you start

You should be comfortable with `kubectl` against a cluster you have admin rights on: namespaces, Deployments, Services, pod labels, `kubectl logs` and `kubectl exec`. No prior Istio experience is assumed, and no Istio object is written in this module.

The playground gives you a single-node `kind` cluster with **Istio 1.30.5 already installed** (the `demo` profile), `istioctl` on your PATH, and two namespaces chosen to contrast with each other:

- **`mesh-demo`** — labelled `istio-injection=enabled`. Holds `api` (an nginx Deployment on port `8080` behind a Service on port `80`, answering `{"service":"api","ok":true}`) and `web` (a client pod with `curl`). Both run `2/2`.
- **`mesh-legacy`** — deliberately **not** injected. Holds `legacy`, the same client image, running `1/1` with no proxy.

There is no `VirtualService`, no `DestinationRule` and no policy of any kind. That is the point: this module is about what the mesh does before you configure it.

## Where this fits

This module is a prerequisite rather than an exam topic. The Istio Certified Associate Traffic Management domain assumes you already know what a sidecar is and can read a proxy's configuration; the sections that follow are graded on writing objects, not on this material.

It earns its place because the rest of the course leans on it constantly. Section 010 names Envoy clusters from the first page. Section 040 is unreadable without knowing which side of a call holds a retry policy. Every module ends by proving a change reached the proxy, using commands introduced here. Skipping it is possible — but then each of those modules has to stop and re-explain a piece of it, which is exactly the problem this module exists to remove.
