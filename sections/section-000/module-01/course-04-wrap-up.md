# Wrap-Up: Mission Debrief

Well flown, astronaut. Before you take your first graded mission, take five minutes to look back at what you learned, check yourself, and land the playground cleanly.

## What you learned

This module was about the communications officer on board every spaceship: the sidecar proxy. You did not write a single Istio object. You learned what already happens before you do.

**From [The Sidecar And The Data Path](./course-01-the-sidecar-and-the-data-path.md):**

- Injection adds an `istio-proxy` container to a pod when the pod is created. Labelling a namespace does not change pods that are already running. You have to restart them.
- `iptables` rules (the Linux firewall inside the pod) send the pod's own traffic through the proxy without the app knowing. Outgoing signals go to port `15001`, incoming signals to port `15006`.
- A request between two meshed pods passes two proxies, so it is logged twice: once by the caller, once by the receiver.
- A pod without a proxy still works, but Istio cannot see its traffic or apply any rule to it.

**From [How The Proxy Gets Its Configuration](./course-02-how-the-proxy-gets-its-configuration.md):**

- `istiod` is mission control. It builds the service registry (the star chart) from Kubernetes and turns it into orders for every proxy.
- Those orders come in four kinds: listeners (LDS), routes (RDS), clusters (CDS) and endpoints (EDS). The proxy takes new orders while it runs, with no restart.
- A request walks down the chain listener → route → cluster → endpoint, and you can read each step with `istioctl proxy-config`.
- An Envoy cluster name such as `outbound|80||api.mesh-demo.svc.cluster.local` tells you the direction, port, subset and host.

**From [The Diagnostic Toolkit](./course-03-the-diagnostic-toolkit.md):**

- Check in this order: `kubectl get`, `istioctl analyze`, `istioctl proxy-status`, `istioctl proxy-config`, then the access log. The first "no" is your answer.
- Each tool has a blind spot. A clean `istioctl analyze` does not prove your labels select anything.
- The response flag in the access log (the ship's black box flight log) tells you where to look. `NR` points at your routing rules. `NC` and `UH` point at the destination.
- Routing decisions happen in the proxy of the pod that **sends** the request, so point your commands at the caller.

## Check yourself

Try to answer each question before you open the answer.

<details>
<summary>1. You label a namespace with <code>istio-injection=enabled</code>. Its pods still show <code>1/1</code>. Why?</summary>

Injection only happens when a pod is created. The pods were running before the label existed. Restart them (for example with `kubectl rollout restart deployment`) and the new pods start with `2/2`.
</details>

<details>
<summary>2. Which proxy decides where a request goes: the caller's or the receiver's?</summary>

The caller's. Routing, retries, timeouts and load balancing all happen in the proxy of the pod that sends the request.
</details>

<details>
<summary>3. Which xDS type carries the list of pod addresses behind a service?</summary>

EDS, the endpoint discovery service. LDS carries listeners, RDS routes, and CDS clusters.
</details>

<details>
<summary>4. The access log shows <code>404</code> with the flag <code>NR</code>. Where do you look first?</summary>

At the routing rules. `NR` means "no route": the request matched no rule. A `503` with `NC` or `UH` would point at the destination instead.
</details>

<details>
<summary>5. <code>istioctl analyze</code> reports no problems. Is your setup correct?</summary>

Not necessarily. It checks that objects agree with each other. It does not check that your labels select any pod or that your rules are in a sensible order.
</details>

## Clean up the playground

The playground is a whole Kubernetes cluster running on your machine. The graded lab builds its own, separate cluster. Remove the playground first, so the two do not compete for memory and you cannot send a command to the wrong solar system by accident.

**Step 1.** Destroy the playground. The command takes the playground's **name**, not its folder path:

```sh
astrona destroy ats-014-playground-000-01
```

**Step 2.** Check that it is gone:

```sh
astrona list
```

`ats-014-playground-000-01` should no longer be in the list.

> [!TIP]
> You can start the playground again at any time with the same `astrona run` command from the module's landing page. It always starts clean, so nothing you broke carries over.

## Your first graded mission

You are ready for the lab: [Which Workloads Are Actually In The Mesh](./labs/lab-01/README.md). Two workloads look healthy but fly without a communications officer. Your job is to find them and bring them into the mesh.

Start the lab:

```sh
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-000/module-01/labs/lab-01
```

Read the task in [`question.md`](./labs/lab-01/question.md) and try it on your own first. When you think you are done, send it for grading:

```sh
astrona submit -c sections/section-000/module-01/labs/lab-01
```

The lab uses the same commands you practised in this module, so keep [The Diagnostic Toolkit](./course-03-the-diagnostic-toolkit.md) open next to it.
