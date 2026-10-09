# Configuring Ingress And Egress Traffic — Ingress

Astronaut, so far every signal you routed was sent from one spaceship in your fleet to another. That is called **east-west** traffic. This section is **north-south**: signals arriving from outside your solar system (the cluster), from clients with no communications officer (sidecar) on board and no place in the mesh.

All three modules bring those signals in through a gateway proxy: the spaceport arrival gate, the one door into your solar system. All three end at the same backend. What differs is the API you write. Istio's own `Gateway` plus `VirtualService` is the full-featured native option. The Kubernetes `Ingress` API is the compatibility path for manifests that already exist. The Kubernetes Gateway API is the portable successor to `Ingress`, which Istio implements, and where new work generally belongs.

Reading all three together is the point of this mission: the ICA expects you to recognise which API a task is written in and to know what each one cannot do.

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

### [Expose A Service With An Istio Ingress Gateway](module-01/course.md)

4 parts and 3 missions:

1. [The Gateway Pod And Its Listener](module-01/course-01-the-gateway-pod-and-its-listener.md)
   - Mission: [Open The Closed Gate Lab](module-01/labs/lab-02/question.md)
2. [Binding Routes With `gateways:`](module-01/course-02-binding-routes-with-gateways.md)
3. [Hosts And References At The Gate](module-01/course-03-hosts-and-references-at-the-gate.md)
   - Mission: [Expose A Service With An Istio Ingress Gateway Lab](module-01/labs/lab-01/question.md)
4. [Diagnosing The Gateway](module-01/course-04-diagnosing-the-gateway.md)
   - Mission: [Repair The Arrival Gate Lab](module-01/labs/lab-03/question.md)
5. [Wrap-Up: Mission Debrief](module-01/course-05-wrap-up.md)

### [Expose A Service With A Kubernetes Ingress](module-02/course.md)

3 parts and 2 missions:

1. [Claiming An Ingress](module-02/course-01-claiming-an-ingress.md)
   - Mission: [Claim The Unclaimed Ingress Lab](module-02/labs/lab-02/question.md)
2. [Rules, Path Types And Translation](module-02/course-02-rules-path-types-and-translation.md)
3. [TLS And The Feature Ceiling](module-02/course-03-tls-and-the-feature-ceiling.md)
   - Mission: [Expose A Service With A Kubernetes Ingress Lab](module-02/labs/lab-01/question.md)
4. [Wrap-Up: Mission Debrief](module-02/course-04-wrap-up.md)

### [Ingress With The Kubernetes Gateway API](module-03/course.md)

4 parts and 3 missions:

1. [Three Objects, Three Owners](module-03/course-01-three-objects-three-owners.md)
2. [A Gateway That Creates Its Own Data Plane](module-03/course-02-a-gateway-that-creates-its-own-data-plane.md)
   - Mission: [Open The Spaceport Gate Lab](module-03/labs/lab-02/question.md)
3. [Attach An HTTPRoute And Read Its Status](module-03/course-03-attach-an-httproute-and-read-its-status.md)
   - Mission: [Fix The Broken Flight Plans Lab](module-03/labs/lab-03/question.md)
4. [Decide Who May Dock](module-03/course-04-decide-who-may-dock.md)
   - Mission: [Share One Gateway Between Two Planets Lab](module-03/labs/lab-01/question.md)
5. [Wrap-Up: Mission Debrief](module-03/course-05-wrap-up.md)

### Capstone

Your final mission for this section: **[Three APIs, One Edge Capstone Lab](capstone/labs/lab-01/README.md)**.

---

<!-- astrona:playground:environment-explain -->
