# Wrap-Up: Mission Debrief

Well flown, astronaut. You have finished every part and every mission in this module. Before you move on, look back at what you learned, check yourself, and land the playground cleanly.

## What you learned

This module was about the Kubernetes Gateway API: a standard way to build the gate that signals from outside your solar system come through, with Istio doing the building.

**From [Three Objects, Three Owners](./course-01-three-objects-three-owners.md):**

- The Gateway API ships as CRDs, apart from Kubernetes and Istio. Without them, `kubectl apply` fails with `no matches for kind "Gateway"`. That is Kubernetes speaking, not Istio.
- `GatewayClass` (cluster-wide) picks the software that builds gates. `Gateway` (in a namespace) describes the doors. `HTTPRoute` (in a namespace) is the flight plan.
- Each object belongs to a different crew: infrastructure, platform and application.
- Istio registers the classes `istio` (controller `istio.io/gateway-controller`) and `istio-remote`.
- Istio's own `Gateway` (`networking.istio.io`) and the Gateway API `Gateway` (`gateway.networking.k8s.io`) share only a name. Check the `apiVersion`.

**From [A Gateway That Creates Its Own Data Plane](./course-02-a-gateway-that-creates-its-own-data-plane.md):**

- A Gateway API `Gateway` with `gatewayClassName: istio` makes Istio create a Deployment and a Service named `<gateway name>-istio` in the `Gateway`'s own namespace. There is no `selector`.
- On `kind`, the annotation `networking.istio.io/service-type: ClusterIP` gives the gate an address. Without it, the `Gateway` stays `Programmed=False`.
- `Accepted` means Istio took the object; `Programmed` means the gate has an address. `PROGRAMMED` turns `True` before the proxy pod is ready.
- A gate with no route answers `404 NR`. The listener only takes signals with its own host name in the `Host` header.
- Delete the `Gateway`, and its proxy goes too.

**From [Attach An HTTPRoute And Read Its Status](./course-03-attach-an-httproute-and-read-its-status.md):**

- An `HTTPRoute` docks at a gate with `parentRefs`, picks signals with `hostnames` and `matches`, and sends them to a Service with `backendRefs`.
- `PathPrefix` matches whole path parts: `/productpage/x` fits `/productpage`, `/productpageX` does not.
- A route reports its status per gate. `Accepted` is about the gate side, `ResolvedRefs` about the backend side.
- A backend typo gives `ResolvedRefs=False BackendNotFound` and signals get `500 NC`.
- A `parentRefs` typo gives no status at all: `status.parents` is empty.
- Subsets, load balancing and outlier detection stay in a `DestinationRule`, which still applies to signals an `HTTPRoute` sends.

**From [Decide Who May Dock](./course-04-decide-who-may-dock.md):**

- `allowedRoutes.namespaces.from` is `Same` by default. A route from another namespace is refused with `Accepted=False NotAllowedByListeners`.
- A route in another namespace needs `namespace` in its `parentRefs`.
- `Selector` lets in only namespaces with a chosen label, and that includes the `Gateway`'s own namespace.
- A route whose host names do not fit the listener is refused with `NoMatchingListenerHostname`.

## Your missions

You proved each skill in a graded mission, right after the part that taught it:

| Mission | After the part | What you proved |
| --- | --- | --- |
| [Open The Spaceport Gate](./labs/lab-02/README.md) | A Gateway That Creates Its Own Data Plane | build a `Gateway` that fits a waiting route, and find its proxy |
| [Fix The Broken Flight Plans](./labs/lab-03/README.md) | Attach An HTTPRoute And Read Its Status | find a backend typo and a gate typo from the status lights |
| [Share One Gateway Between Two Planets](./labs/lab-01/README.md) | Decide Who May Dock | build a shared gate and let routes from two namespaces dock |

If you skipped one, go back to it now. Each mission is short, and the exam asks for exactly these skills.

## Check yourself

Try to answer each question before you open the answer.

<details>
<summary>1. <code>kubectl apply</code> of a <code>Gateway</code> fails with <code>no matches for kind "Gateway"</code>. Is Istio broken?</summary>

No. Kubernetes does not know the kind, because the Gateway API CRDs are not installed. Install them, in a version your Istio release supports.
</details>

<details>
<summary>2. You created a Gateway API <code>Gateway</code> named <code>shared</code> in namespace <code>edge</code>. Where is its proxy?</summary>

In namespace `edge`, as a Deployment and a Service named `shared-istio`. Istio built them from the `Gateway`. Nothing appears in `istio-system`.
</details>

<details>
<summary>3. On a <code>kind</code> cluster, your <code>Gateway</code> shows <code>Accepted=True</code> but <code>Programmed=False</code> with <code>AddressNotAssigned</code>. What do you check?</summary>

The Service type. Without the annotation `networking.istio.io/service-type: ClusterIP`, Istio creates a `LoadBalancer` Service, and `kind` has no load balancer to give it an address. The YAML is valid; the gate has no address.
</details>

<details>
<summary>4. A signal through the gate gets <code>404</code>, and the gate's flight log shows <code>NR</code>. Name two causes.</summary>

No route fits the signal. Either no `HTTPRoute` is attached to the gate (for example a typo in `parentRefs`, or the gate refused the route), or the attached routes have no rule for that host name or path.
</details>

<details>
<summary>5. An <code>HTTPRoute</code> shows <code>Accepted=True</code> and <code>ResolvedRefs=False</code>. Which half do you fix?</summary>

The backend half. The gate took the route, but a Service in `backendRefs` was not found. The reason `BackendNotFound` and the message name the missing Service. Signals get `500 NC`.
</details>

<details>
<summary>6. <code>kubectl get httproute scout -o yaml</code> shows <code>status: parents: []</code>. What is wrong?</summary>

No gate answered for the route. Check the name and the namespace in `parentRefs`. A route in another namespace than the gate must name the gate's namespace.
</details>

<details>
<summary>7. A route in namespace <code>outpost</code> is refused with <code>NotAllowedByListeners</code>. The gate uses <code>from: Selector</code> with <code>gateway-access: "true"</code>. What do you do?</summary>

Label the namespace: `kubectl label namespace outpost gateway-access=true`. The selector matches namespace labels. Remember that the gate's own namespace needs the label too.
</details>

<details>
<summary>8. You route with an <code>HTTPRoute</code>. Where do you set outlier detection for the backend?</summary>

In a `DestinationRule` for that Service. The Gateway API has no field for it, and a `DestinationRule` applies to a Service whichever route sent the signal there.
</details>

## Clean up the playground

Your playground is a whole Kubernetes cluster running on your machine. When you are done with this module, remove it, and any mission that is still running.

First, see what is still running:

```sh
astrona list
```

Remove the playground. The command takes its **name**, not its folder path:

```sh
astrona destroy ats-014-playground-060-03
```

If `astrona list` also showed a mission, remove it the same way, for example:

```sh
astrona destroy ats-014-lab-060-03-03
```

Then check that everything is gone:

```sh
astrona list
```

```text
No astrona labs running.
```

You can start the playground again at any time with the `astrona run` command from the module's landing page. It always starts clean, so nothing you broke carries over.

> *The `GatewayClass` picks the builder, the `Gateway` builds the gate, and the `HTTPRoute` steers the signals: read their status lights, and they tell you which one to fix.*
