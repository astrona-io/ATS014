# Defining Traffic Policies With Destination Rules

Astronaut, your flight plan (the `VirtualService`) now gets every signal to the right beacon. But a beacon is a call sign that a whole squadron of spaceships (pods) answers to, and each signal still has to land on just one ship. Picking that ship is this section's mission. Later sections add two more questions: how many channels to hold open to a ship, and when a ship has misbehaved enough to be pulled out of formation. All of those are `DestinationRule` decisions, made by the communications officer on the *calling* ship, and they live under one field: `trafficPolicy`.

This section covers the endpoint-selection half of that field, and the precedence rules that govern every other key in it. The resilience half (connection pools, outlier detection and locality) is section 040. It is the same object with different keys.

**Curriculum item covered:** Defining Traffic Policies with Destination Rules

---

## What You Will Master

- Where endpoint selection sits in the request path: route match, then cluster selection, then endpoint choice.
- `loadBalancer.simple` and what `ROUND_ROBIN`, `LEAST_REQUEST`, `RANDOM` and `PASSTHROUGH` each do — including why `LEAST_REQUEST` looks slightly uneven.
- `loadBalancer.consistentHash` over a header, a cookie, a query parameter or the source IP.
- The ring-hash mechanism: why no state is stored, and why changing the endpoint set moves only about `1/N` of sessions.
- That affinity (making the same astronaut always reach the same ship) is best effort: an optimisation, not a substitute for shared session state.
- The silent fallback: a request with nothing to hash gets ordinary load balancing, with no error.
- Istio generating a session cookie when `httpCookie.ttl` is set, and why leaving `ttl` out is sometimes right.
- `trafficPolicy` at host, subset and port level, and that a more specific one **replaces** rather than merges.
- Reading `lbPolicy` per cluster from `istioctl proxy-config cluster` to prove a subset override took effect.

---

## The Learning Path

Work through the modules in this order, astronaut. For each one: read the parts with its playground open next to you, clean up the playground, then take its graded mission. Finish with the capstone, which brings the whole section together.

### 1. Load Balancer Policy And Session Affinity
*   **Module Reader:** **[Load Balancer Policy And Session Affinity](./module-01/course.md)**
    1. [Endpoint Selection And The `simple` Algorithms](./module-01/course-01-endpoint-selection-and-simple-algorithms.md)
    2. [`consistentHash` And The Ring](./module-01/course-02-consistent-hash-and-the-ring.md)
    3. [Policy Levels And Verification](./module-01/course-03-policy-levels-and-verification.md)
*   **Hands-on Playground:** `sections/section-030/module-01/playground` — a kind cluster with Istio 1.30.5 (Helm) and namespace `bookinfo`: `httpbin` with three v1 pods and one v2 pod, a `curl` client and access logs. No DestinationRule yet.
    ```bash
    astrona run --git ssh://git@github.com/astrona-io/ATS014.git -c sections/section-030/module-01/playground
    ```
*   **Practice Lab Sandbox:** **`sections/section-030/module-01/labs/lab-01`**
*   **Lab Run Command:**
    ```bash
    astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-030/module-01/labs/lab-01
    ```
*   **Hands-on Objective:** Pin users to endpoints with host-level consistent hashing, override that policy for one subset only, and prove from the proxy's own cluster dump that the two subsets really are using different algorithms.
*   **Second Practice Lab:** **`sections/section-030/module-01/labs/lab-02`** — affinity for clients that carry no identifier.
    ```bash
    astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-030/module-01/labs/lab-02
    ```
*   **Hands-on Objective:** Pin browser sessions with a cookie Istio issues itself, attached through `portLevelSettings` rather than to the whole host — then show that a client which sends no cookie is deliberately not pinned.

### 2. Section Capstone Challenge
*   **Comprehensive Challenge:** **`sections/section-030/capstone/labs/lab-01` (Sticky Sessions With A Shadowed Canary)**
*   **Lab Run Command:**
    ```bash
    astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-030/capstone/labs/lab-01
    ```
*   **Hands-on Objective:** Combine this section's two-level `trafficPolicy` with section 020's mirroring on one host — sticky sessions on the stable subset, a spreading policy on the canary, and every caller request copied to the canary without a single caller ever reaching it.

---

The playground is your training solar system in the simulator. It is ungraded: it spins up, prepares the environment, and waits. There is no task and no `astrona submit`. Tear it down with `astrona destroy <name>` when you are finished. The name is printed in the module's playground callout.
