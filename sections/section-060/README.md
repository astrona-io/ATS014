# Configuring Ingress And Egress Traffic — Ingress

Astronaut, so far every signal you routed was sent from one spaceship in your fleet to another. That is called **east-west** traffic. This section is **north-south**: signals arriving from outside your solar system (the cluster), from clients with no communications officer (sidecar) on board and no place in the mesh.

All three modules bring those signals in through a gateway proxy: the spaceport arrival gate, the one door into your solar system. All three end at the same backend. What differs is the API you write. Istio's own `Gateway` plus `VirtualService` is the full-featured native option. The Kubernetes `Ingress` API is the compatibility path for manifests that already exist. The Kubernetes Gateway API is the portable successor to `Ingress`, which Istio implements, and where new work generally belongs.

Reading all three together is the point of this mission: the ICA expects you to recognise which API a task is written in and to know what each one cannot do.

**Curriculum item covered:** Configuring Ingress and Egress Traffic (ingress half; the egress half is section 080)

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

## The Learning Path

Work through the modules in this order, astronaut. For each one: read the parts with its playground open next to you, clean up the playground, then take its graded mission. Finish with the capstone, which brings the whole section together.

### 1. Expose A Service With An Istio Ingress Gateway
*   **Module Reader:** **[Expose A Service With An Istio Ingress Gateway](./module-01/course.md)**
    1. [The Gateway Pod And Its Listener](./module-01/course-01-the-gateway-pod-and-its-listener.md)
    2. [Binding Routes With `gateways:`](./module-01/course-02-binding-routes-with-gateways.md)
    3. [Diagnosing The Gateway](./module-01/course-03-diagnosing-the-gateway.md)
*   **Hands-on Playground:** `sections/section-060/module-01/playground` — a kind cluster with Istio 1.30.5 (Helm), an ingress gateway in namespace `istio-ingress` (label `istio=ingress`) forwarded to `127.0.0.1:8080`, and Bookinfo plus `httpbin` in `bookinfo`. No Gateway or VirtualService yet.
    ```bash
    astrona run --git ssh://git@github.com/astrona-io/ATS014.git -c sections/section-060/module-01/playground
    ```
*   **Practice Lab Sandbox:** **`sections/section-060/module-01/labs/lab-01`**
*   **Lab Run Command:**
    ```bash
    astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-060/module-01/labs/lab-01
    ```
*   **Hands-on Objective:** Open one listener for two hostnames, attach an application to each, and prove from the gateway's own route table that both landed — while an unknown host and a crossed host are both rejected.

### 2. Expose A Service With A Kubernetes Ingress
*   **Module Reader:** **[Expose A Service With A Kubernetes Ingress](./module-02/course.md)**
    1. [Claiming An Ingress](./module-02/course-01-claiming-an-ingress.md)
    2. [Rules, Path Types And Translation](./module-02/course-02-rules-path-types-and-translation.md)
    3. [TLS And The Feature Ceiling](./module-02/course-03-tls-and-the-feature-ceiling.md)
*   **Hands-on Playground:** `sections/section-060/module-02/playground` — namespace `k8s-ingress-demo`, with no `Ingress` and no `IngressClass` yet.
    ```bash
    astrona run --git ssh://git@github.com/astrona-io/ATS014.git -c sections/section-060/module-02/playground
    ```
*   **Practice Lab Sandbox:** **`sections/section-060/module-02/labs/lab-01`**
*   **Lab Run Command:**
    ```bash
    astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-060/module-02/labs/lab-01
    ```
*   **Hands-on Objective:** Have Istio's gateway serve a plain Kubernetes `Ingress` with both path types and TLS — including putting the secret in the namespace that actually works, which is not the one the `Ingress` is in.

### 3. Ingress With The Kubernetes Gateway API
*   **Module Reader:** **[Ingress With The Kubernetes Gateway API](./module-03/course.md)**
    1. [Three Objects, Three Owners](./module-03/course-01-three-objects-three-owners.md)
    2. [A Gateway That Creates Its Own Data Plane](./module-03/course-02-a-gateway-that-creates-its-own-data-plane.md)
    3. [`HTTPRoute`, Status And What Stays In Istio](./module-03/course-03-httproute-status-and-what-stays-in-istio.md)
*   **Hands-on Playground:** `sections/section-060/module-03/playground` — namespace `gwapi-demo`, with the Gateway API CRDs installed and Istio's `istio` `GatewayClass` registered.
    ```bash
    astrona run --git ssh://git@github.com/astrona-io/ATS014.git -c sections/section-060/module-03/playground
    ```
*   **Practice Lab Sandbox:** **`sections/section-060/module-03/labs/lab-01`**
*   **Lab Run Command:**
    ```bash
    astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-060/module-03/labs/lab-01
    ```
*   **Hands-on Objective:** Create a Gateway that brings its own proxy, then let a route from a *different* namespace attach to it via a `Selector` grant — the attachment this API denies by default.

### 4. Section Capstone Challenge
*   **Comprehensive Challenge:** **`sections/section-060/capstone/labs/lab-01` (Three APIs, One Edge)**
*   **Lab Run Command:**
    ```bash
    astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-060/capstone/labs/lab-01
    ```
*   **Hands-on Objective:** Expose three applications at once, one through each API, and prove the two data planes are separate. The Gateway API host must 404 on the shared gateway.

---

Each playground is ungraded: a training solar system that spins up, prepares itself, and waits for you. There is no task and no `astrona submit`. Tear one down with `astrona destroy <name>` when you are finished — the name is printed in each module's playground callout.
