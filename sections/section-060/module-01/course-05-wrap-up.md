# Wrap-Up: Mission Debrief

Well flown, astronaut. You have finished every part and every mission in this module. Before you move on, look back at what you learned, check yourself, and land the playground cleanly.

## What you learned

This module was about the spaceport arrival gate: the ingress gateway, and the two objects that set it up. The `Gateway` opens the gate, and a `VirtualService` linked to it says where each arriving signal flies next.

**From [The Gateway Pod And Its Listener](./course-01-the-gateway-pod-and-its-listener.md):**

- The ingress gateway is the same Envoy program as every sidecar, running alone in its own pod (`1/1`) on its own planet, `istio-ingress` here. A Kubernetes Service puts it in front of the outside world.
- A `Gateway` opens a listener on the pods its `selector` matches. It has no destination and routes nothing by itself.
- The `selector` label depends on the install: `istio: ingress` for the Helm chart used here, `istio: ingressgateway` for an `istioctl` install. Check with `kubectl get pods -n istio-ingress -L istio`.
- A selector that matches no pod gives `000` (no reply), no port `80` listener on the gateway, and `IST0101 Referenced selector not found`.
- A correct `Gateway` with no flight plan gives `404 NR`: a listener on port `80` that points at an empty route table `http.80`.

**From [Binding Routes With `gateways:`](./course-02-binding-routes-with-gateways.md):**

- A flight plan reaches the gate only when its `gateways:` field names the `Gateway`.
- Leaving out `gateways:` means the hidden value `mesh`: all sidecars. The gate answers `404 NR`, its route table holds only `blackhole:80`, and `istioctl analyze` stays clean.
- Naming a gateway replaces `mesh`. List both if ships inside the mesh need the same routes.
- `istioctl proxy-config routes` on the gateway shows your host, your paths and the flight plan they came from, such as `bridge.starfleet`.

**From [Hosts And References At The Gate](./course-03-hosts-and-references-at-the-gate.md):**

- The gate uses a flight plan only where the `Gateway` hosts and the `VirtualService` hosts overlap. No overlap gives `404` and the warning `IST0132`.
- `*` on the `Gateway` alone does not accept every signal: the flight plan still needs a matching host.
- A route at the gate can use subsets, weights and everything else a route in the mesh can.
- A bare gateway name is looked up on the flight plan's own planet. Use `<namespace>/<name>` for a `Gateway` elsewhere; a wrong namespace gives `404` and `IST0101 Referenced gateway not found`.

**From [Diagnosing The Gateway](./course-04-diagnosing-the-gateway.md):**

- `000` is my gate, `404` is my flight plan, `503` is my ship.
- Two `404`s can have different causes. The host field in the flight log and the gateway's route table tell them apart.
- A route to a ship that does not exist gives `503 NC cluster_not_found` and `IST0101 Referenced host not found`.
- `istioctl proxy-config listener`, `routes` and `endpoints` on the gateway follow a signal from port to route to ship.

## Your missions

You proved each skill in a graded mission, right after the part that taught it:

| Mission | After the part | What you proved |
| --- | --- | --- |
| [Open The Closed Gate](./labs/lab-02/README.md) | The Gateway Pod And Its Listener | find a selector that matches no gateway pod and open the gate |
| [Expose A Service With An Istio Ingress Gateway](./labs/lab-01/README.md) | Hosts And References At The Gate | open one gate for two hosts and steer each host to its own ship |
| [Repair The Arrival Gate](./labs/lab-03/README.md) | Diagnosing The Gateway | find and fix several faults at the gate, one result code at a time |

If you skipped one, go back to it now. Each mission is short, and the exam asks for exactly these skills.

## Check yourself

Try to answer each question before you open the answer.

<details>
<summary>1. How is the ingress gateway different from a sidecar?</summary>

It is the same Envoy program, but it runs alone in its own pod (`1/1`, no app), usually on its own planet, and a Kubernetes Service puts it in front of the outside world. It handles north-south signals from outside the mesh. A sidecar sits inside an app pod and handles that ship's signals.
</details>

<details>
<summary>2. You apply a <code>Gateway</code> and every signal gets <code>000</code>. What do you check first?</summary>

The `selector`. Compare it with the gateway pod's labels (`kubectl get pods -n istio-ingress -L istio`). If no pod matches, no listener opens. `istioctl proxy-config listener` on the gateway shows no port `80`, and `istioctl analyze` reports `IST0101 Referenced selector not found`.
</details>

<details>
<summary>3. Your <code>Gateway</code> is correct, and you have no <code>VirtualService</code> yet. What does the gate answer?</summary>

`404` with the flag `NR` in the gate's flight log. The listener exists, but its route table holds no route.
</details>

<details>
<summary>4. Your flight plan looks right, the gate answers <code>404 NR</code>, and <code>istioctl analyze</code> is clean. What is the most likely cause?</summary>

A missing `gateways:` field. Without it, the flight plan applies to `mesh` (the sidecars) and never reaches the gate. The gate's route table shows only `blackhole:80`.
</details>

<details>
<summary>5. The <code>Gateway</code> lists <code>starfleet.example.com</code> and the flight plan lists <code>shop.example.com</code>. What happens?</summary>

The two host lists do not overlap, so the gate ignores the flight plan for every host and answers `404`. `istioctl analyze` warns with `IST0132`.
</details>

<details>
<summary>6. Your flight plan lives in <code>starfleet</code>, and the <code>Gateway</code> lives in <code>edge</code>. What do you write in <code>gateways:</code>?</summary>

`edge/<gateway name>`. A bare name is looked up on the flight plan's own planet, `starfleet`, where no such `Gateway` exists.
</details>

<details>
<summary>7. The gate answers <code>503</code> and the flight log shows <code>NC cluster_not_found</code>. Is routing broken?</summary>

No. Routing worked: a route matched. The destination it names does not exist, often a typo in `destination.host`. `istioctl analyze` reports `IST0101 Referenced host not found`.
</details>

<details>
<summary>8. You want to test the gate with curl. Why do you send <code>-H "Host: ..."</code>?</summary>

The gate chooses its listener host and its routes by the `Host` header. Without it, curl sends the address you dialled, such as `localhost:8080`, which matches no host on the `Gateway`, and you get `404`.
</details>

## Clean up the playground

Your playground is a whole Kubernetes cluster running on your machine. When you are done with this module, remove it, and any mission that is still running.

First, see what is still running:

```sh
astrona list
```

Remove the playground. The command takes its **name**, not its folder path:

```sh
astrona destroy ats-014-playground-060-01
```

If `astrona list` also showed a mission, remove it the same way, for example:

```sh
astrona destroy ats-014-lab-060-01-03
```

Then check that everything is gone:

```sh
astrona list
```

```text
No astrona labs running.
```

You can start the playground again at any time with the `astrona run` command from the module's landing page. It always starts clean, so nothing you broke carries over.

> *Two objects open the arrival gate: the `Gateway` opens a listener on the gateway pods, and a `VirtualService` that names it in `gateways:` says where each signal flies next.*
