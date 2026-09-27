# Section 060: Configuring Ingress Traffic

Everything up to here was east-west: one meshed workload calling another. This section is north-south — requests arriving from outside the cluster, from clients with no sidecar and no membership in the mesh.

All three modules put traffic through a gateway proxy, and all three end at the same backend. What differs is the API you write. Istio's own `Gateway` plus `VirtualService` is the full-featured native option. The Kubernetes `Ingress` API is the compatibility path for manifests that already exist. The Kubernetes Gateway API is the portable successor to `Ingress`, which Istio implements, and where new work generally belongs.

Reading all three together is the point: the ICA expects you to recognise which API a task is written in and to know what each one cannot do.

**Curriculum item covered:** Configuring Ingress and Egress Traffic (ingress half; the egress half is section 080)

---

## What You Will Master

- The ingress gateway as a standalone Envoy — one container, no application, reached through a Service — and that every `proxy-config` command works on it unchanged.
- `Gateway` opening a listener by port, protocol and hostname, found by a **pod label `selector`**, with the object in your namespace and the pod in `istio-system`.
- `VirtualService` binding routes with **`gateways:`**, the reserved `mesh` value, and why omitting the field produces a silent 404.
- Host overlap between the two objects, and `<namespace>/<name>` for a cross-namespace `Gateway`.
- Reading a gateway 404 apart from a 503 — "404 is my config, 503 is my backend" — and the route dump that separates the two kinds of 404.
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

### 1. Expose A Service With An Istio Ingress Gateway
*   **Module Reader:** **[Module 1: Expose A Service With An Istio Ingress Gateway](./module-01/course.md)**
    1. [The Gateway Pod And Its Listener](./module-01/course-01-the-gateway-pod-and-its-listener.md)
    2. [Binding Routes With `gateways:`](./module-01/course-02-binding-routes-with-gateways.md)
    3. [Diagnosing The Gateway](./module-01/course-03-diagnosing-the-gateway.md)
*   **Hands-on Playground:** `sections/section-060/module-01/playground` — namespace `ingress-demo` with `booking-service` and an unconfigured `istio-ingressgateway`.
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
*   **Module Reader:** **[Module 2: Expose A Service With A Kubernetes Ingress](./module-02/course.md)**
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
*   **Module Reader:** **[Module 3: Ingress With The Kubernetes Gateway API](./module-03/course.md)**
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
*   **Hands-on Objective:** Expose three applications simultaneously, one through each API, and prove the two data planes are separate — the Gateway API host must 404 on the shared gateway.

---

Each playground is ungraded: it spins up, prepares the environment, and waits. There is no task and no `astrona submit`. Tear one down with `astrona destroy <name>` when you are finished — the name is printed in each module's playground callout.
