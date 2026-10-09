# Configuring Ingress And Egress Traffic — Ingress

Traffic between pods inside the mesh is called **east-west** traffic. This section is about **north-south** traffic: requests that arrive from outside the cluster, from clients that have no sidecar proxy and are not part of the mesh.

All three modules bring those requests in through an ingress gateway: an Envoy proxy at the edge of the mesh that accepts traffic from outside the cluster. All three end at the same backend. What differs is the API you write. Istio's own `Gateway` plus `VirtualService` is the full-featured native option. The Kubernetes `Ingress` API is the compatibility path for manifests that already exist. The Kubernetes Gateway API is the portable successor to `Ingress`, which Istio implements, and where new work generally belongs.

Reading all three together is the point of this section: the ICA expects you to recognise which API a task is written in and to know what each one cannot do.

**Curriculum item covered:** Configuring Ingress and Egress Traffic (the ingress half)

---

## What You Will Master

- The ingress gateway as a standalone Envoy — one container, no application, reached through a Service — and that every `proxy-config` command works on it unchanged.
- `Gateway` opening a listener by port, protocol and hostname, found by a **pod label `selector`**, with the object in your namespace and the pod in `istio-system`.
- `VirtualService` binding routes with **`gateways:`**, the reserved `mesh` value, and why omitting the field produces a silent 404.
- Host overlap between the two objects, and `<namespace>/<name>` for a cross-namespace `Gateway`.
- Reading a gateway 404 apart from a 503 — "404 is my configuration, 503 is my backend" — and the route dump that separates the two kinds of 404.
- Serving a Kubernetes `Ingress` through Istio with `ingressClassName: istio` and controller `istio.io/ingress-controller`.
- What an unclaimed `Ingress` looks like: a valid object with `CLASS: <none>` that nothing serves.
- Why an `Ingress` TLS secret must live in the **gateway's** namespace, and the HTTP-fine/HTTPS-dead signature when it does not.
- `pathType: Prefix` being **element-wise**, unlike Istio's `uri.prefix` — the same word, two semantics.
- Exactly what the `Ingress` API cannot express: weights, mirroring, header matching, retries, timeouts, faults, subsets, gateway selection, rule ordering.
- Gateway API's three objects and three owners, and that its CRDs are not part of core Kubernetes.
- A Gateway API `Gateway` **creating** its own proxy Deployment in its own namespace, with a lifecycle tied to the object.
- `allowedRoutes` as deny-by-default cross-namespace attachment, including the `Selector` form.
- `HTTPRoute` as a `VirtualService` translation: `parentRefs`, `hostnames`, `matches`, `backendRefs`, `weight`, `filters`.
- Diagnosing with status conditions — `Accepted`, `Programmed`, `ResolvedRefs` — and what each `False` points at.
- The line around the Gateway API: `DestinationRule` policy and Istio's faults, retries and timeouts still apply to routes it carries.

---

## Modules In This Section

Work through the modules in this order. Each part teaches one idea. A mission (a graded lab) comes right after the part it practises, and the last page of each module is a wrap-up. The capstone at the end uses everything in the section at once.

### Expose A Service With An Istio Ingress Gateway

4 parts and 3 missions:

1. The Gateway Pod And Its Listener
   - Mission: Open The Closed Gate Lab
2. Binding Routes With `gateways:`
3. Hosts And References At The Gate
   - Mission: Expose A Service With An Istio Ingress Gateway Lab
4. Diagnosing The Gateway
   - Mission: Repair The Arrival Gate Lab
5. Wrap-Up: Mission Debrief

### Expose A Service With A Kubernetes Ingress

3 parts and 2 missions:

1. Claiming An Ingress
   - Mission: Claim The Unclaimed Ingress Lab
2. Rules, Path Types And Translation
3. TLS And The Feature Ceiling
   - Mission: Expose A Service With A Kubernetes Ingress Lab
4. Wrap-Up: Mission Debrief

### Ingress With The Kubernetes Gateway API

4 parts and 3 missions:

1. Three Objects, Three Owners
2. A Gateway That Creates Its Own Data Plane
   - Mission: Open The Spaceport Gate Lab
3. Attach An HTTPRoute And Read Its Status
   - Mission: Fix The Broken Flight Plans Lab
4. Decide Who May Dock
   - Mission: Share One Gateway Between Two Planets Lab
5. Wrap-Up: Mission Debrief

### Capstone

The section ends with a capstone lab that uses everything in it: **Three APIs, One Edge Capstone Lab**.

---

<!-- astrona:playground:environment-explain -->
