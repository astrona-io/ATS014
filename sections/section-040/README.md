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

## Modules In This Section

Work through the modules in this order. Each part teaches one idea. A mission (a graded lab) comes right after the part it practises, and the last page of each module is a wrap-up. The capstone at the end uses everything in the section at once.

### [Timeouts And Retries](module-01/course.md)

4 parts and 3 missions:

1. [Set An Abort Window](module-01/course-01-set-an-abort-window.md)
2. [Test A Timeout Across Two Ships](module-01/course-02-test-a-timeout-across-two-ships.md)
   - Mission: [Free The Shuttle From A Slow Navcom Lab](module-01/labs/lab-02/question.md)
3. [Re-Send Lost Signals](module-01/course-03-re-send-lost-signals.md)
   - Mission: [Retry Only The Signals Worth Re-Sending Lab](module-01/labs/lab-03/question.md)
4. [Share One Clock, Retry What Is Safe](module-01/course-04-share-one-clock-and-retry-what-is-safe.md)
   - Mission: [Timeouts And Retries Lab](module-01/labs/lab-01/question.md)
5. [Wrap-Up: Mission Debrief](module-01/course-05-wrap-up.md)

### [Circuit Breaking With Connection Pool Limits](module-02/course.md)

3 parts and 2 missions:

1. [The Connection Pool](module-02/course-01-the-connection-pool.md)
2. [Overflow And Its Signatures](module-02/course-02-overflow-and-its-signatures.md)
   - Mission: [Circuit Breaking With Connection Pool Limits Lab](module-02/labs/lab-01/question.md)
3. [Scope, Verification And Retry Amplification](module-02/course-03-scope-verification-and-retry-amplification.md)
   - Mission: [Calm The Retry Storm Lab](module-02/labs/lab-02/question.md)
4. [Wrap-Up: Mission Debrief](module-02/course-04-wrap-up.md)

### [Outlier Detection And Endpoint Ejection](module-03/course.md)

3 parts and 2 missions:

1. [Passive Health Checking](module-03/course-01-passive-health-checking.md)
2. [Ejection Mechanics And Limits](module-03/course-02-ejection-mechanics-and-limits.md)
   - Mission: [Outlier Detection And Endpoint Ejection Lab](module-03/labs/lab-01/question.md)
3. [Local, Temporary, And Verified](module-03/course-03-local-temporary-and-verified.md)
   - Mission: [Raise Both Shields Lab](module-03/labs/lab-02/question.md)
4. [Wrap-Up: Mission Debrief](module-03/course-04-wrap-up.md)

### [Locality Load Balancing And Failover](module-04/course.md)

3 parts and 3 missions:

1. [Where Locality Comes From](module-04/course-01-where-locality-comes-from.md)
   - Mission: [Give Every Ship Its Orbit Lab](module-04/labs/lab-02/question.md)
2. [Preference, Distribute And Failover](module-04/course-02-preference-distribute-and-failover.md)
   - Mission: [Split Signals Between Two Orbits Lab](module-04/labs/lab-03/question.md)
3. [The Health Dependency And Scope](module-04/course-03-the-health-dependency-and-scope.md)
   - Mission: [Locality Load Balancing And Failover Lab](module-04/labs/lab-01/question.md)
4. [Wrap-Up: Mission Debrief](module-04/course-04-wrap-up.md)

### Capstone

Your final mission for this section: **[A Resilient Payment Path Capstone Lab](capstone/labs/lab-01/README.md)**.

---

<!-- astrona:playground:environment-explain -->
