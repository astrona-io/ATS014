# Defining Traffic Policies With Destination Rules

A `VirtualService` gets a request as far as a destination. Something still has to pick one pod out of that destination, and — in later sections — decide how many connections to hold open to it and when it has misbehaved enough to be taken out of rotation. All of those are `DestinationRule` decisions, made by the *calling* proxy, and they live under one field: `trafficPolicy`.

This section covers the endpoint-selection half of that field, and the precedence rules that govern every other key in it. The resilience half — connection pools, outlier detection and locality — is section 040, and it is the same object with different keys.

**Curriculum item covered:** Defining Traffic Policies with Destination Rules

---

## What You Will Master

- Where endpoint selection sits in the request path: route match, then cluster selection, then endpoint choice.
- `loadBalancer.simple` and what `ROUND_ROBIN`, `LEAST_REQUEST`, `RANDOM` and `PASSTHROUGH` each do — including why `LEAST_REQUEST` looks slightly uneven.
- `loadBalancer.consistentHash` over a header, a cookie, a query parameter or the source IP.
- The ring-hash mechanism: why no state is stored, and why changing the endpoint set moves only about `1/N` of sessions.
- That affinity is best effort — an optimisation, not a substitute for shared session state.
- The silent fallback: a request with nothing to hash gets ordinary load balancing, with no error.
- Istio generating a session cookie when `httpCookie.ttl` is set, and why leaving `ttl` out is sometimes right.
- `trafficPolicy` at host, subset and port level, and that a more specific one **replaces** rather than merges.
- Reading `lbPolicy` per cluster from `istioctl proxy-config cluster` to prove a subset override took effect.

---

## The Learning Path

### 1. Load Balancer Policy And Session Affinity
*   **Module Reader:** **[Load Balancer Policy And Session Affinity](./module-01/course.md)**
    1. [Endpoint Selection And The `simple` Algorithms](./module-01/course-01-endpoint-selection-and-simple-algorithms.md)
    2. [`consistentHash` And The Ring](./module-01/course-02-consistent-hash-and-the-ring.md)
    3. [Policy Levels And Verification](./module-01/course-03-policy-levels-and-verification.md)
*   **Hands-on Playground:** `sections/section-030/module-01/playground` — a kind cluster with Istio installed and namespace `lb-demo` holding a three-replica `httpbin` plus a client pod, with no `DestinationRule` yet.
    ```bash
    astrona run --git ssh://git@github.com/astrona-io/ATS014.git -c sections/section-030/module-01/playground
    ```
*   **Practice Lab Sandbox:** **`sections/section-030/module-01/labs/lab-01`**
*   **Lab Run Command:**
    ```bash
    astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-030/module-01/labs/lab-01
    ```
*   **Hands-on Objective:** Pin users to endpoints with host-level consistent hashing, override that policy for one subset only, and prove from the proxy's own cluster dump that the two subsets really are using different algorithms.

### 2. Section Capstone Challenge
*   **Comprehensive Challenge:** **`sections/section-030/capstone/labs/lab-01` (Sticky Sessions With A Shadowed Canary)**
*   **Lab Run Command:**
    ```bash
    astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-030/capstone/labs/lab-01
    ```
*   **Hands-on Objective:** Combine this section's two-level `trafficPolicy` with section 020's mirroring on one host — sticky sessions on the stable subset, a spreading policy on the canary, and every caller request copied to the canary without a single caller ever reaching it.

---

The playground is ungraded: it spins up, prepares the environment, and waits. There is no task and no `astrona submit`. Tear it down with `astrona destroy <name>` when you are finished — the name is printed in the module's playground callout.
