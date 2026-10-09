# Wrap-Up: Mission Debrief

Well flown, astronaut. You have finished every part and every mission in this module. Before you move on, look back at what you learned, check yourself, and land the playground cleanly.

## What you learned

This module was about the communications officer on board every spaceship: the sidecar proxy. You did not write a single Istio object. You learned what already happens before you do.

**From [Meet The Communications Officer](./course-01-meet-the-communications-officer.md):**

- A namespace with the label `istio-injection: enabled` gets an `istio-proxy` container in every **new** pod. Pods that were already running need a restart.
- `istio-proxy` is a native sidecar: an init container with `restartPolicy: Always`, started before the app. A pod with one app container shows `2/2`.
- `1/1` where you expected `2/2` means there is no communications officer on board.

**From [Follow A Signal Through Two Proxies](./course-02-follow-a-signal-through-two-proxies.md):**

- `iptables` rules send the pod's own signals through the proxy without the app knowing: outgoing to port `15001`, incoming to port `15006`.
- A signal between two meshed ships passes two proxies and is logged twice: `outbound` by the sender, `inbound` by the receiver.
- A ship without a proxy still reaches the mesh, but no Istio rule applies to what it sends. Routing is decided by the **sender's** proxy.

**From [How Mission Control Sends Orders](./course-03-how-mission-control-sends-orders.md):**

- `istiod` (mission control) builds the service registry (the star chart) from Kubernetes and sends every proxy its orders over xDS, with no restart.
- The four kinds of orders are LDS (Listener Discovery Service), RDS (Route Discovery Service), CDS (Cluster Discovery Service) and EDS (Endpoint Discovery Service).
- `istioctl proxy-status` lists every connected proxy; naming one proxy shows whether it holds exactly what was sent (`Match`).

**From [Read The Proxy's Orders Layer By Layer](./course-04-read-the-proxys-orders-layer-by-layer.md):**

- A signal walks down the chain listener, route, cluster, endpoint, and `istioctl proxy-config` reads each layer.
- A cluster name like `outbound|8000||probe.starfleet.svc.cluster.local` gives the direction, the Service port, the subset and the host.
- The cluster carries the Service port, the endpoint the container port. By default every proxy carries the whole star chart.

**From [The Diagnostic Toolkit](./course-05-the-diagnostic-toolkit.md):**

- Check in this order: `kubectl get`, `istioctl analyze`, `istioctl proxy-status`, `istioctl proxy-config`, then the flight log. The first "no" is your answer.
- A clean `istioctl analyze` does not prove that your labels select anything.
- The response flag tells the failures apart: `NR` (404) points at routing, `NC` and `UH` (503) at the destination.

## Your missions

You proved each skill in a graded mission, right after the part that taught it:

| Mission | After the part | What you proved |
| --- | --- | --- |
| [Which Workloads Are Actually In The Mesh](./labs/lab-01/README.md) | Follow A Signal Through Two Proxies | find workloads without a communications officer and bring them into the mesh |
| [Find The Missing Supply Ship](./labs/lab-02/README.md) | The Diagnostic Toolkit | walk the checklist to an empty destination and fix it |

If you skipped one, go back to it now. Each mission is short.

## Check yourself

Try to answer each question before you open the answer.

<details>
<summary>1. You label a namespace with <code>istio-injection=enabled</code>. Its pods still show <code>1/1</code>. Why?</summary>

Injection only happens when a pod is created. The pods were running before the label existed. Restart them (for example with `kubectl rollout restart deployment`) and the new pods start with `2/2`.
</details>

<details>
<summary>2. Where is <code>istio-proxy</code> listed in an injected pod's spec?</summary>

Under `initContainers`, with `restartPolicy: Always`. That makes it a native sidecar: started before the app, and running for the pod's whole life.
</details>

<details>
<summary>3. Which proxy decides where a signal goes: the sender's or the receiver's?</summary>

The sender's. Routing, retries, timeouts and load balancing all happen in the proxy of the ship that sends the signal.
</details>

<details>
<summary>4. A ship without a proxy calls a meshed service. Which flight logs show the signal?</summary>

Only the receiver's, with an `inbound` line. There is no proxy on the sender to write an `outbound` line, and no Istio rule applies on the way out.
</details>

<details>
<summary>5. Which xDS type carries the list of pod addresses behind a destination?</summary>

EDS, the Endpoint Discovery Service. LDS carries listeners, RDS routes, and CDS clusters.
</details>

<details>
<summary>6. A cluster is named <code>outbound|8000||probe.starfleet.svc.cluster.local</code>, and its endpoints use port <code>8080</code>. Is something wrong?</summary>

No. The cluster name carries the Service port (`8000`), and the endpoints carry the container port (`8080`). The empty field between `||` means there is no subset.
</details>

<details>
<summary>7. The flight log shows <code>404</code> with the flag <code>NR</code>. Where do you look first?</summary>

At the routing rules. `NR` means "no route": the signal matched no rule. A `503` with `NC` or `UH` would point at the destination instead.
</details>

<details>
<summary>8. <code>istioctl analyze</code> reports no problems. Is your setup correct?</summary>

Not necessarily. It checks that objects agree with each other. It does not check that your labels select any pod, or that your rules are in a sensible order.
</details>

## Clean up the playground

Your playground is a whole Kubernetes cluster running on your machine. When you are done with this module, remove it, and any mission that is still running.

First, see what is still running:

```sh
astrona list
```

Remove the playground. The command takes its **name**, not its folder path:

```sh
astrona destroy ats-014-playground-000-01
```

If `astrona list` also showed a mission, remove it the same way, for example:

```sh
astrona destroy ats-014-lab-000-01-02
```

Then check that everything is gone:

```sh
astrona list
```

```text
No astrona labs running.
```

You can start the playground again at any time with the `astrona run` command from the module's landing page. It always starts clean, so nothing you broke carries over.

> *A communications officer on every ship, mission control behind them, and four layers of orders in between: read those, and you can explain anything the mesh does.*
