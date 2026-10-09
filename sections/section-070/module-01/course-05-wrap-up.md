# Wrap-Up: Mission Debrief

Well flown, astronaut. You have finished every part and every mission in this module. Before you move on, look back at what you learned, check yourself, and land the playground cleanly.

## What you learned

This module was about the edge of your solar system: which planets outside it your ships may signal, and how to put Istio's rules on them.

**From [The Outbound Traffic Policy](./course-01-the-outbound-traffic-policy.md):**

- The service registry is the star chart: every Kubernetes Service and every `ServiceEntry` a proxy may see.
- `ALLOW_ANY` (the default) lets uncharted hosts through as `PassthroughCluster`, with no rules. `REGISTRY_ONLY` refuses them as `BlackHoleCluster`.
- Set it for the whole mesh with `meshConfig.outboundTrafficPolicy.mode`, or for one namespace with `outboundTrafficPolicy` on a `Sidecar`.
- A refusal is a cut connection (`000`, exit code `35` or `56`), or a `502` with the route `block_all` when the proxy has an HTTP listener on that port.
- `REGISTRY_ONLY` is enforced by the sidecar. A pod without one is not limited.

**From [The `ServiceEntry` Object](./course-02-the-serviceentry-object.md):**

- Four fields matter: `hosts`, `ports` (with `protocol`), `location` and `resolution`.
- `protocol: HTTP` turns on HTTP features. `HTTPS` and `TLS` only let the proxy read the SNI name. `TCP` moves bytes.
- `MESH_EXTERNAL` is for somebody else's API, with no mutual TLS. `MESH_INTERNAL` is for your own workloads outside Kubernetes.
- `resolution: DNS` shows as `STRICT_DNS` in the proxy. A wildcard host needs `resolution: NONE`.
- Every port the application uses must be on the chart: an entry for `443` does nothing for `http://` on `80`.

**From [A Registered Host Is An Ordinary Host](./course-03-a-registered-host-is-an-ordinary-host.md):**

- A `VirtualService` timeout works on an external host, but only on a port declared `HTTP`. The timeout shows as `504` with `UT`.
- When the host has several ports, name the port in the route, or `istioctl analyze` reports `IST0112`. A route to a port that is not on the chart gives `IST0101`.
- A `DestinationRule` connection pool becomes Envoy circuit breaker limits. Signals over the limit get `503` with `UO`.
- A `ServiceEntry` is exported to every namespace unless `exportTo` says otherwise.

**From [When A Correct ServiceEntry Is Refused](./course-04-when-a-correct-serviceentry-is-refused.md):**

- A ship can use a `ServiceEntry` only if its `exportTo` includes the ship's namespace, and the ship's `Sidecar` `egress.hosts` takes in the entry's namespace.
- A hidden entry gives the same refusal as a missing one, and `istioctl analyze` stays quiet.
- `istioctl proxy-config cluster` on the ship shows whether it can see the host.
- The clean default: put the entry in the namespace of the ships that use it, with `exportTo: ["."]`.

## Your missions

You proved each skill in a graded mission, right after the part that taught it:

| Mission | After the part | What you proved |
| --- | --- | --- |
| [Open Exactly One Route Out](./labs/lab-01/README.md) | A Registered Host Is An Ordinary Host | chart one outside endpoint, keep another blocked, and put a timeout on the open one |
| [Reach The Hidden Relay](./labs/lab-02/README.md) | When A Correct ServiceEntry Is Refused | find a chart entry the `Sidecar` hides, and a port declared with the wrong protocol |

If you skipped one, go back to it now. Each mission is short, and the exam asks for exactly these skills.

## Check yourself

Try to answer each question before you open the answer.

<details>
<summary>1. A fresh mesh, no <code>ServiceEntry</code>. A pod calls <code>https://httpbin.org</code>. What happens, and what does the flight log say?</summary>

It works. The default is `ALLOW_ANY`, so the proxy lets the signal through. The flight log names `PassthroughCluster`, and Istio applies no rules to it.
</details>

<details>
<summary>2. Under <code>REGISTRY_ONLY</code>, an HTTPS call gives <code>000</code>. How do you tell a refusal from a network failure?</summary>

Read the caller's flight log. `BlackHoleCluster` means the mesh refused it: the host is not on the star chart. No flight log line at all points to DNS or the network.
</details>

<details>
<summary>3. A plain HTTP call to an uncharted host returns <code>502</code>, not <code>000</code>. Why?</summary>

Another charted host uses the same port as `HTTP`, so the proxy has an HTTP listener there. It reads the request, finds no route except `block_all`, and answers `502` itself.
</details>

<details>
<summary>4. You need one namespace locked down without reinstalling the control plane. What do you write?</summary>

A `Sidecar` in that namespace, with no `workloadSelector`, `outboundTrafficPolicy.mode: REGISTRY_ONLY`, and `egress.hosts` such as `./*` and `istio-system/*`.
</details>

<details>
<summary>5. Your <code>VirtualService</code> sets <code>timeout: 2s</code> on an external host, but a slow call still takes 5 seconds. What do you check?</summary>

The protocol of the `ServiceEntry` port. Only a port declared `HTTP` lets the proxy read requests. With `HTTPS` or `TCP`, the timeout has nothing to measure.
</details>

<details>
<summary>6. You want to chart every host under <code>wikipedia.org</code>. Which <code>resolution</code> do you use, and why?</summary>

`NONE`. DNS cannot look up `*.wikipedia.org`, because it is not a single name. The proxy forwards the signal to the address the application already looked up.
</details>

<details>
<summary>7. A <code>ServiceEntry</code> in <code>default</code> works for one namespace and not for another. <code>istioctl analyze</code> is clean. Where do you look first?</summary>

For a `Sidecar` in the failing namespace. If its `egress.hosts` does not take in `default`, the entry is off that planet's star chart. Then check the entry's `exportTo`. Confirm with `istioctl proxy-config cluster` on a ship in the failing namespace.
</details>

<details>
<summary>8. Why is <code>exportTo: ["."]</code> a good default for a <code>ServiceEntry</code> under <code>REGISTRY_ONLY</code>?</summary>

Without it, the entry is exported to every namespace. One team's allow-list then silently opens the host for every planet in the mesh.
</details>

## Clean up the playground

Your playground is a whole Kubernetes cluster running on your machine. When you are done with this module, remove it, and any mission that is still running.

First, see what is still running:

```sh
astrona list
```

Remove the playground. The command takes its **name**, not its folder path:

```sh
astrona destroy ats-014-playground-070-01
```

If `astrona list` also showed a mission, remove it the same way, for example:

```sh
astrona destroy ats-014-lab-070-01-02
```

Then check that everything is gone:

```sh
astrona list
```

```text
No astrona labs running.
```

You can start the playground again at any time with the `astrona run` command from the module's landing page. It always starts clean, so nothing you broke carries over.

> *A `ServiceEntry` puts a planet from another solar system on the star chart. `REGISTRY_ONLY` makes the chart the only way out, and the declared protocol decides how much of Istio you can use on the way.*
