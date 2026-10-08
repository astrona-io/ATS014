# Using Resilience Features (Circuit Breaking, Failover, Outlier Detection, Timeouts, Retries)

Astronaut, this is the section where things break in space. Every spaceship (pod) in the fleet depends on ships it does not control. A signal can get lost, a ship can be overloaded, a ship can be damaged, and a whole planet's squadron can go dark.

Resilience features are what the **calling** ship can do about that, without any help from the ship it is calling. It can set an abort window (a timeout), re-send a lost signal (a retry), raise its shields instead of queueing work it cannot finish (a circuit breaker), pull a damaged ship out of formation (outlier detection), and prefer ships orbiting a planet that still works (locality failover).

All four modules configure the **calling** side. Nothing here requires the backend to change, and nothing here protects the server: a connection pool is per client, and an ejection is one communications officer's (one proxy's) private decision. The exam keeps coming back to that point.

The modules build on each other, and so do their failure modes. Timeouts and retries share one clock. Circuit breaking is the pool that retries can overwhelm. Outlier detection is what marks an endpoint bad, and locality failover cannot work without it. Put together, they stop one failing ship from becoming a Death Star: one weak spot that takes the whole fleet down.

**Curriculum item covered:** Using Resilience Features (circuit breaking, failover, outlier detection, timeouts, retries)

---

## What You Will Master

- Route `timeout` as a deadline measured by the **client's** proxy, producing a synthesised 504 with the `UT` flag — and why it never stops the upstream's work.
- `retries` with `attempts`, `perTryTimeout` and `retryOn`, including which conditions exist and why 4xx is never retried.
- The off-by-one: `attempts` counts retries *after* the first try; Envoy calls it `numRetries`.
- Istio's implicit default retry policy, and that only `attempts: 0` disables it.
- The budget rule — `timeout ≥ (attempts + 1) × perTryTimeout` — and the 504 that signals you broke it.
- Splitting a route by `method` so writes are never retried.
- `connectionPool` TCP and HTTP limits as a two-stage queue, enforced per client, capping concurrency rather than volume.
- Identifying a breaker rejection by the `UO` flag and `upstream_rq_pending_overflow`, and confirming it by the backend's silence.
- Why the backend's exposure is `limit × callers`, and why this is not rate limiting.
- `outlierDetection` as **passive** health checking, and how it differs in kind from a readiness probe.
- `maxEjectionPercent` defaulting to 10% — and therefore ejecting nothing from a small pool.
- Ejection expiring and lengthening with each repeat, producing a cycle rather than a steady state.
- Why an ejection is one proxy's private verdict while `kubectl get endpoints` never moves.
- Locality from `topology.kubernetes.io/region` and `/zone`, with the `istio-locality` pod-label override.
- That locality preference is already the default, and `localityLbSetting` exists to change it.
- `distribute` versus `failover`, their mutual exclusion, and why `failover` is region-level.
- **The section's headline fact:** locality failover has no health checker of its own, so without `outlierDetection` it never fires.
- Reading it all back with `istioctl proxy-config` and `pilot-agent request GET stats`.

---

## The Learning Path

Work through the modules in this order, astronaut. For each one: read the parts with its playground open next to you, clean up the playground, then take its graded mission. Finish with the capstone, which brings the whole section together.

### 1. Timeouts And Retries
*   **Module Reader:** **[Timeouts And Retries](./module-01/course.md)**
    1. [The Route Timeout](./module-01/course-01-the-route-timeout.md)
    2. [The Retry Policy](./module-01/course-02-the-retry-policy.md)
    3. [The Shared Budget And Idempotency](./module-01/course-03-the-shared-budget-and-idempotency.md)
*   **Hands-on Playground:** `sections/section-040/module-01/playground` — namespace `bookinfo` with Bookinfo, `httpbin` v1/v2 whose `/delay` and `/status` endpoints make failure controllable, a `curl` client, and the `reviews` route that sends jason to v2.
    ```bash
    astrona run --git ssh://git@github.com/astrona-io/ATS014.git -c sections/section-040/module-01/playground
    ```
*   **Practice Lab Sandbox:** **`sections/section-040/module-01/labs/lab-01`**
*   **Lab Run Command:**
    ```bash
    astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-040/module-01/labs/lab-01
    ```
*   **Hands-on Objective:** Retry the read path and deliberately not the write path, with a timeout budget that actually lets the retries run — then prove the attempt counts from the server's own log.

### 2. Circuit Breaking With Connection Pool Limits
*   **Module Reader:** **[Circuit Breaking With Connection Pool Limits](./module-02/course.md)**
    1. [The Connection Pool](./module-02/course-01-the-connection-pool.md)
    2. [Overflow And Its Signatures](./module-02/course-02-overflow-and-its-signatures.md)
    3. [Scope, Verification And Retry Amplification](./module-02/course-03-scope-verification-and-retry-amplification.md)
*   **Hands-on Playground:** `sections/section-040/module-02/playground` — namespace `bookinfo` with `httpbin` (v1 + v2) and a `fortio` load generator whose sidecar keeps the circuit-breaker counters, because concurrency is the whole subject.
    ```bash
    astrona run --git ssh://git@github.com/astrona-io/ATS014.git -c sections/section-040/module-02/playground
    ```
*   **Practice Lab Sandbox:** **`sections/section-040/module-02/labs/lab-01`**
*   **Lab Run Command:**
    ```bash
    astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-040/module-02/labs/lab-01
    ```
*   **Hands-on Objective:** Cap concurrent outstanding work, then prove the cap is real by showing the same total request count succeeding sequentially and failing concurrently — with `UO` in the log and nothing at all in the backend's.

### 3. Outlier Detection And Endpoint Ejection
*   **Module Reader:** **[Outlier Detection And Endpoint Ejection](./module-03/course.md)**
    1. [Passive Health Checking](./module-03/course-01-passive-health-checking.md)
    2. [Ejection Mechanics And Limits](./module-03/course-02-ejection-mechanics-and-limits.md)
    3. [Local, Temporary, And Verified](./module-03/course-03-local-temporary-and-verified.md)
*   **Hands-on Playground:** `sections/section-040/module-03/playground` — namespace `bookinfo` with two healthy `httpbin` pods, a `curl` client that keeps the outlier counters, and `fortio`. Adding the pod that answers 503 to everything is your first step.
    ```bash
    astrona run --git ssh://git@github.com/astrona-io/ATS014.git -c sections/section-040/module-03/playground
    ```
*   **Practice Lab Sandbox:** **`sections/section-040/module-03/labs/lab-01`**
*   **Lab Run Command:**
    ```bash
    astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-040/module-03/labs/lab-01
    ```
*   **Hands-on Objective:** Get a client proxy to notice a failing endpoint on its own and stop using it — choosing a `maxEjectionPercent` that can actually act — while Kubernetes goes on insisting the pod is perfectly ready.

### 4. Locality Load Balancing And Failover
*   **Module Reader:** **[Locality Load Balancing And Failover](./module-04/course.md)**
    1. [Where Locality Comes From](./module-04/course-01-where-locality-comes-from.md)
    2. [Preference, `distribute` And `failover`](./module-04/course-02-preference-distribute-and-failover.md)
    3. [The Health Dependency And Scope](./module-04/course-03-the-health-dependency-and-scope.md)
*   **Hands-on Playground:** `sections/section-040/module-04/playground` — namespace `locality-demo` with two zoned backends. Single-node, so locality is declared with the `istio-locality` pod label; see the playground's `docs/overview.md` for what that does and does not show.
    ```bash
    astrona run --git ssh://git@github.com/astrona-io/ATS014.git -c sections/section-040/module-04/playground
    ```
*   **Practice Lab Sandbox:** **`sections/section-040/module-04/labs/lab-01`**
*   **Lab Run Command:**
    ```bash
    astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-040/module-04/labs/lab-01
    ```
*   **Hands-on Objective:** Move traffic out of a locality whose endpoint is failing — which means configuring the thing that decides what "failing" means, because a locality setting on its own never fails over.

### 5. Section Capstone Challenge
*   **Comprehensive Challenge:** **`sections/section-040/capstone/labs/lab-01` (A Resilient Payment Path)**
*   **Lab Run Command:**
    ```bash
    astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-040/capstone/labs/lab-01
    ```
*   **Hands-on Objective:** All four features on one service at once — differing retry policies for reads and writes, a connection pool that rejects overflow, outlier detection that removes a poisoned replica, and locality awareness on top. The interactions are the test: retries add concurrency to a full pool, and they hide from the caller the very failures the detector needs to see.

---

Each playground is an ungraded training solar system: it spins up, prepares the environment, and waits for you. There is no task and no `astrona submit`. Tear one down with `astrona destroy <name>` when you are finished. The name is printed in each module's playground callout.
