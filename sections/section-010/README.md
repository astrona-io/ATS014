# Configuring Routing Within A Service Mesh

A Kubernetes Service load balances over pods. It cannot look at a request, and it cannot be told that some requests matter differently from others. Istio's answer is a proxy beside every pod plus two objects that describe, declaratively, what that proxy should do with the traffic it sees.

This section covers both ends of that idea. Module 1 is the request's journey: how a rule matches, which destination it picks, what else a matched rule can do to it, and how to prove the rule reached the proxy. Module 2 is the opposite direction — how much the proxy should be told about in the first place, and how to cut a full service registry down to the handful of hosts a workload actually calls.

**Curriculum item covered:** Configuring Routing within a Service Mesh

---

## What You Will Master

- The division of labour between `VirtualService` (where a request goes) and `DestinationRule` (what the named destinations mean).
- How `istiod` turns the registry into Envoy clusters, and how to read the `outbound|port|subset|host` cluster name.
- Defining subsets over pod labels, and why a subset whose labels match nothing is legal configuration and a later 503.
- Matching on `headers`, `uri`, `queryParams` and `method`, with the `exact` / `prefix` / `regex` forms and RE2's limits.
- The AND/OR rule: conditions inside one `-` entry are ANDed, separate entries are ORed.
- Top-down first-match evaluation, and why a default route placed first silently kills everything below it.
- Short host names resolving relative to the object's own namespace — and the failures that causes.
- The two failure signatures: wrong-destination-no-error versus bare 503, and which half of the module each points at.
- What a sidecar is programmed with by default, how xDS delivers it, and why the cost scales with the cluster.
- Narrowing with `Sidecar` and `egress[].hosts` in `<namespace>/<host>` form, and why `istio-system/*` is boilerplate.
- `Sidecar` precedence: selective beats namespace default beats root namespace, and each replaces rather than merges.
- Why `Sidecar` is a configuration control rather than a security boundary, and what to combine it with.
- Using `redirect`, `rewrite`, `headers` and `corsPolicy` on a matched rule, and which of them ends the request.
- How a Service port's name or `appProtocol` decides the protocol — and the silent fallback to plain TCP that disables every HTTP feature.
- What a `tcp` or `tls` rule can match on when there is no request to read, and what per-connection balancing costs you.
- Reading a proxy's live configuration with `istioctl proxy-config routes`, `cluster`, `endpoints` and `listener`.

---

## The Learning Path

### 1. Route Requests Within The Mesh
*   **Module Reader:** **[Route Requests Within The Mesh](./module-01/course.md)**
    1. [Subsets And The Destination Vocabulary](./module-01/course-01-subsets-and-destination-vocabulary.md)
    2. [Matching A Request](./module-01/course-02-matching-a-request.md)
    3. [Evaluation Order, Name Resolution And Proof](./module-01/course-03-evaluation-order-and-proof.md)
    4. [Rewriting, Redirecting And Headers](./module-01/course-04-rewriting-redirecting-and-headers.md)
    5. [Routing Non-HTTP Traffic](./module-01/course-05-routing-non-http-traffic.md)
*   **Hands-on Playground:** `sections/section-010/module-01/playground` — a kind cluster with Istio installed and namespace `routing-demo` holding two versions of one service plus a client pod. No routing configured.
    ```bash
    astrona run --git ssh://git@github.com/astrona-io/ATS014.git -c sections/section-010/module-01/playground
    ```
*   **Practice Lab Sandbox:** **`sections/section-010/module-01/labs/lab-01`**
*   **Lab Run Command:**
    ```bash
    astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-010/module-01/labs/lab-01
    ```
*   **Hands-on Objective:** Split one Service into `v1` and `v2` subsets and route by header, URI prefix and query parameter, with a default that catches everything else — then prove with live traffic that all three specific rules are still reachable and a near-miss falls through.
*   **Second Practice Lab:** **`sections/section-010/module-01/labs/lab-02`** — the fields beside `route`.
    ```bash
    astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-010/module-01/labs/lab-02
    ```
*   **Hands-on Objective:** Redirect a legacy prefix without touching a pod, rewrite a path family onto a backend that has never heard of it, stamp a response header, strip an internal request header, and allow exactly one CORS origin — then prove the rewrite from the compiled route, because no access log will show it to you.

### 2. Scope Proxy Configuration With The Sidecar Resource
*   **Module Reader:** **[Scope Proxy Configuration With The Sidecar Resource](./module-02/course.md)**
    1. [What A Proxy Is Programmed With](./module-02/course-01-what-a-proxy-is-programmed-with.md)
    2. [The Sidecar Object And Its Host Language](./module-02/course-02-the-sidecar-object-and-host-language.md)
    3. [Precedence, Reachability And What It Is Not](./module-02/course-03-precedence-reachability-and-limits.md)
*   **Hands-on Playground:** `sections/section-010/module-02/playground` — a kind cluster with Istio installed and two injected namespaces, `sidecar-demo` and `sidecar-other`, so scoping has a visible effect.
    ```bash
    astrona run --git ssh://git@github.com/astrona-io/ATS014.git -c sections/section-010/module-02/playground
    ```
*   **Practice Lab Sandbox:** **`sections/section-010/module-02/labs/lab-01`**
*   **Lab Run Command:**
    ```bash
    astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-010/module-02/labs/lab-01
    ```
*   **Hands-on Objective:** Cut a namespace's proxy configuration down from the whole registry to its own namespace plus `istio-system` plus one named namespace, prove the reduction from the proxy's own cluster dump, and show that a third namespace is now unreachable while its workload is still running.

### 3. Section Capstone Challenge
*   **Comprehensive Challenge:** **`sections/section-010/capstone/labs/lab-01` (Route And Scope A Storefront)**
*   **Lab Run Command:**
    ```bash
    astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-010/capstone/labs/lab-01
    ```
*   **Hands-on Objective:** Deliver both halves at once on a mesh with no configuration — subsets and three reachable match rules over a default, plus a namespace-wide `Sidecar` that keeps the local namespace, `istio-system` and one partner namespace while scoping a third out entirely. The halves interact: a `Sidecar` that forgets `./*` destroys the routing you just built.

---

Each playground is ungraded: it spins up, prepares the environment, and waits. There is no task and no `astrona submit`. Tear one down with `astrona destroy <name>` when you are finished — the name is printed in each module's playground callout.
