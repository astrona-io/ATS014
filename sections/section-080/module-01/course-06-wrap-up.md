# Wrap-Up: Mission Debrief

Well flown, astronaut. You have finished every part and every mission in this module. Before you move on, look back at what you learned, check yourself, and land the playground cleanly.

## What you learned

This module was about the departure gate: one checked exit for every signal that leaves your solar system, and the flight plan that sends signals there.

**From [A Gateway That Carries Nothing](./course-01-a-gateway-that-carries-nothing.md):**

- The egress gateway is a standalone Envoy proxy behind its own Service. The Helm chart labels its pods `istio: egress`, the `demo` profile `istio: egressgateway`.
- It catches nothing by itself. Without a flight plan, every sidecar flies straight to the outside host, and the gate's flight log stays empty.
- An ingress gateway is addressed; an egress gateway is chosen.

**From [Open The Departure Gate](./course-02-open-the-departure-gate.md):**

- The `Gateway` names the **outside** host in `servers[].hosts`: read it from the gate's point of view.
- `tls.mode: PASSTHROUGH` passes the sealed stream on without decrypting it.
- The `DestinationRule` on the gate's Service has a subset with no labels. It narrows nothing, but hop 1 names it, so it must exist.
- A `PASSTHROUGH` server gets no listener until a `VirtualService` routes the host through the gate.

**From [The Two-Stage `VirtualService`](./course-03-the-two-stage-virtualservice.md):**

- One `VirtualService` holds two rules: hop 1 for `mesh` (every sidecar) and hop 2 for the gate.
- The top-level `gateways` list must name both. Each rule's `match.gateways` says which proxy runs it.
- HTTPS passed through needs `tls` rules on `sniHosts`. Plain HTTP uses `http` rules on the port.
- `istioctl proxy-config listener` shows hop 1 on the shuttle and hop 2 on the gate.

**From [Prove The Hop, And Break It](./course-04-prove-the-hop-and-break-it.md):**

- A `200` proves nothing. Read hop 1 in the shuttle's flight log and hop 2 in the gate's.
- `mesh` missing: `200`, straight out, and `istioctl analyze` stays quiet.
- Hop 2 missing, or a `Gateway` that does not serve the host: the gate has no listener, and the shuttle logs `UF,URX` with `Connection_refused` (`IST0132` for the `Gateway`).
- The `DestinationRule` missing: `NC` in the shuttle's log, `IST0101` in `istioctl analyze`.

**From [Choose Who Flies Through The Gate](./course-05-choose-who-flies-through-the-gate.md):**

- `sourceLabels` on hop 1 sends only the labelled ships through the gate.
- On Istio 1.30.5, a `tls` hop 1 needs `gateways: [mesh]` next to `sourceLabels`; an `http` hop 1 must leave `gateways` out of the `match`.
- It narrows the route, not the permission: an unlabelled ship still flies direct.
- Real egress control needs the route, `REGISTRY_ONLY`, and an `AuthorizationPolicy` plus a `NetworkPolicy`.
- The gate gives one flight log, one source address and one place for policy, and costs an extra hop and a component on the critical path.

## Your missions

You proved each skill in a graded mission, right after the part that taught it:

| Mission | After the part | What you proved |
| --- | --- | --- |
| [Repair The Departure Gate](./labs/lab-02/README.md) | Prove The Hop, And Break It | find why signals skip the gate, and why the gate then refuses them |
| [Send One Ship Through The Departure Gate](./labs/lab-01/README.md) | Choose Who Flies Through The Gate | build the four objects over plain HTTP, prove the hop, and divert only one client |

If you skipped one, go back to it now. Each mission is short, and the exam asks for exactly these skills.

## Check yourself

Try to answer each question before you open the answer.

<details>
<summary>1. An egress gateway is installed and healthy. Does outgoing traffic use it?</summary>

No. It catches nothing by itself. Only a `VirtualService` with a hop 1 rule for `mesh` sends signals to it. Count the lines in its flight log to be sure.
</details>

<details>
<summary>2. What goes in <code>servers[].hosts</code> of an egress <code>Gateway</code>, and why?</summary>

The outside host, for example `httpbin.org`. The gate serves signals bound for that host, and that is the name it matches on: the `Host` header for HTTP, the SNI name for TLS.
</details>

<details>
<summary>3. Why does the <code>DestinationRule</code> for the gate's Service have a subset with no labels?</summary>

It gives hop 1 a named cluster per outside host, so the configuration and the flight logs keep the hosts apart. It narrows nothing, but once hop 1 names the subset, deleting it gives `NC`.
</details>

<details>
<summary>4. What does <code>mesh</code> mean in a <code>gateways</code> list?</summary>

It is the reserved name for every sidecar in the mesh. In the top-level list it makes the sidecars get the flight plan. In a rule's `match` it says the rule runs in the sidecars.
</details>

<details>
<summary>5. The shuttle gets <code>200</code>, but the gate's flight log is empty. What do you check first?</summary>

The shuttle's flight log: if it ends at an internet address, hop 1 never ran. Then check that the top-level `gateways` list of the `VirtualService` names `mesh`.
</details>

<details>
<summary>6. The shuttle gets <code>000</code>, and its log shows <code>UF,URX</code> with <code>Connection_refused</code> to the gate's pod. What is wrong?</summary>

The gate has no listener for the host. Either hop 2 is missing, or the `Gateway` does not serve the host. `istioctl proxy-config listener` on the gate shows it, and `istioctl analyze` reports `IST0132` for the second case.
</details>

<details>
<summary>7. Why does HTTPS through the gate use <code>tls</code> rules with <code>sniHosts</code>?</summary>

The traffic stays encrypted the whole way, so neither proxy can read the HTTP request. The only name they can read is the SNI name from the TLS handshake.
</details>

<details>
<summary>8. You add <code>sourceLabels</code> to hop 1. Is a ship without the label blocked from the internet?</summary>

No. It skips hop 1 and flies direct, past the gate. Blocking needs `REGISTRY_ONLY`, an `AuthorizationPolicy` on the gate and a `NetworkPolicy`.
</details>

## Clean up the playground

Your playground is a whole Kubernetes cluster running on your machine. When you are done with this module, remove it, and any mission that is still running.

First, see what is still running:

```sh
astrona list
```

Remove the playground. The command takes its **name**, not its folder path:

```sh
astrona destroy ats-014-playground-080-01
```

If `astrona list` also showed a mission, remove it the same way, for example:

```sh
astrona destroy ats-014-lab-080-01-02
```

Then check that everything is gone:

```sh
astrona list
```

```text
No astrona labs running.
```

You can start the playground again at any time with the `astrona run` command from the module's landing page. It always starts clean, so nothing you broke carries over.

> *An egress gateway is a departure gate only when a flight plan sends signals there. Read both flight logs, and remember that a narrowed route is not a locked door.*
