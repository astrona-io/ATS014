# Section 020: Configuring Traffic Shifting

Releasing a new version is a traffic problem before it is a deployment problem. The pods are easy to start; the hard questions are how many real requests reach them, and how fast you can change your mind.

Istio gives two answers and this section covers both. Weighted routing moves a controllable percentage of live traffic to the new version — real users, real responses, reversible in one apply. Mirroring sends the new version a *copy* of production traffic and throws the answer away, so it sees real load while no user is exposed to it. They solve the same problem from opposite ends, and choosing between them is a real decision: weights give you the candidate's answers, mirroring gives you its behaviour under load with no way to compare output.

**Curriculum item covered:** Configuring Traffic Shifting

---

## What You Will Master

- Several weighted destinations in one `route` block, with `weight` beside `destination` and the 100-sum rule enforced at admission.
- How a weight becomes a per-request draw inside Envoy, and why cluster selection happens before endpoint load balancing.
- Running a canary as a sequence of applies, and rolling back in one — the reason the feature is worth the configuration.
- Why a merge patch on any list-valued field replaces the list rather than editing it.
- Measuring a statistical split honestly: what 10, 100 and 1000 samples can each tell you.
- Why traffic share and replica count are independent — the section's most testable idea.
- `mirror` as a sibling of `route`, a single destination whose response *and latency* are discarded.
- Why a mirror is never part of the weighted split, and that a full mirror doubles internal request volume.
- `mirrorPercentage` for sampling, and that omitting it means 100%, not 0%.
- The `-shadow` authority suffix, what it is for, and why the receiving proxy's access log is the only proof a mirror works.
- The three-state mirror diagnostic: policy absent, policy present but no endpoints, or working.
- That the mesh discards the mirrored response but not the work the shadow did — and what that means before mirroring anything with side effects.
- Reading `weightedClusters` and `requestMirrorPolicies` out of a live proxy.

---

## The Learning Path

### 1. Shift Traffic With Weighted Routing
*   **Module Reader:** **[Module 1: Shift Traffic With Weighted Routing](./module-01/course.md)**
    1. [Weighted Destinations](./module-01/course-01-weighted-destinations.md)
    2. [Running A Rollout](./module-01/course-02-running-a-rollout.md)
    3. [Weight Versus Replicas, And Proof](./module-01/course-03-weight-versus-replicas-and-proof.md)
*   **Hands-on Playground:** `sections/section-020/module-01/playground` — a kind cluster with Istio installed and namespace `shifting-demo` holding two versions with distinguishable responses, plus a client pod.
    ```bash
    astrona run --git ssh://git@github.com/astrona-io/ATS014.git -c sections/section-020/module-01/playground
    ```
*   **Practice Lab Sandbox:** **`sections/section-020/module-01/labs/lab-01`**
*   **Lab Run Command:**
    ```bash
    astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-020/module-01/labs/lab-01
    ```
*   **Hands-on Objective:** Run a 70/30 canary with an internal-tester header rule pinned above the weights, prove the split over 200 requests, and leave the replica counts alone — because share is a weight, not a pod count.

### 2. Mirror Live Traffic To A Shadow Service
*   **Module Reader:** **[Module 2: Mirror Live Traffic To A Shadow Service](./module-02/course.md)**
    1. [Mirror As A Sibling Of Route](./module-02/course-01-mirror-as-a-sibling-of-route.md)
    2. [Identifying And Sampling Shadow Traffic](./module-02/course-02-identifying-and-sampling-shadow-traffic.md)
    3. [Consequences, Verification And Limits](./module-02/course-03-consequences-verification-and-limits.md)
*   **Hands-on Playground:** `sections/section-020/module-02/playground` — the same shape in namespace `mirror-demo`, with no routing configured so the mirror is yours to add.
    ```bash
    astrona run --git ssh://git@github.com/astrona-io/ATS014.git -c sections/section-020/module-02/playground
    ```
*   **Practice Lab Sandbox:** **`sections/section-020/module-02/labs/lab-01`**
*   **Lab Run Command:**
    ```bash
    astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-020/module-02/labs/lab-01
    ```
*   **Hands-on Objective:** Serve every caller from the stable version while a full copy of each request reaches the release candidate — then prove the shadow received them, using the one piece of evidence a perfectly happy caller can never show you.

### 3. Section Capstone Challenge
*   **Comprehensive Challenge:** **`sections/section-020/capstone/labs/lab-01` (Canary And Shadow At The Same Time)**
*   **Lab Run Command:**
    ```bash
    astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-020/capstone/labs/lab-01
    ```
*   **Hands-on Objective:** Put both features on one rule — an internal-tester match above an 80/20 weighted default that also mirrors every request to a separate shadow Service — and keep them straight, because a mirror written as a route destination silently becomes a traffic split.

---

Each playground is ungraded: it spins up, prepares the environment, and waits. There is no task and no `astrona submit`. Tear one down with `astrona destroy <name>` when you are finished — the name is printed in each module's playground callout.
