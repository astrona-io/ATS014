# Using Resilience Features (Circuit Breaking, Failover, Outlier Detection, Timeouts, Retries)

This section is about failure. Every pod in the mesh depends on services it does not control. A request can get lost, a service can be overloaded, a pod can start returning errors, and every pod in one zone can go down at once.

Resilience features are what the **calling** side can do about that, without any change to the service it calls. It can stop waiting after a set time (a timeout), send a failed request again (a retry), reject requests at once instead of queueing work that cannot finish (circuit breaking), remove a failing endpoint for a while (outlier detection), and prefer endpoints in a locality that still works (locality failover).

All four modules configure the **calling** side. Nothing here requires the backend to change, and nothing here protects the server. A connection pool limit applies per client, and an ejection is the decision of one proxy only. The exam keeps coming back to that point.

The modules build on each other, and so do their failure modes. Timeouts and retries share one time budget. Circuit breaking limits the connection pool that retries can fill up. Outlier detection is what marks an endpoint as failing, and locality failover cannot work without it. Together they stop one failing service from becoming a single point of failure for the whole application.

**Curriculum item covered:** Using Resilience Features (circuit breaking, failover, outlier detection, timeouts, retries)

---

## What You Will Master

- Route `timeout` as a deadline measured by the **client's** proxy, producing a synthesised 504 with the `UT` flag — and why it never stops the upstream's work.
- `retries` with `attempts`, `perTryTimeout` and `retryOn`, including which conditions exist and why 4xx is never retried.
- The off-by-one: `attempts` counts retries *after* the first try; Envoy calls it `numRetries`.
- Istio's implicit default retry policy, and that only `attempts: 0` disables it.
- The budget rule — `timeout ≥ (attempts + 1) × perTryTimeout` — and the 504 that shows you broke it.
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

### Timeouts And Retries

4 parts and 3 missions:

1. Set An Abort Window
2. Test A Timeout Across Two Ships
   - Mission: Free The Shuttle From A Slow Navcom Lab
3. Re-Send Lost Signals
   - Mission: Retry Only The Signals Worth Re-Sending Lab
4. Share One Clock, Retry What Is Safe
   - Mission: Timeouts And Retries Lab
5. Wrap-Up: Mission Debrief

### Circuit Breaking With Connection Pool Limits

3 parts and 2 missions:

1. The Connection Pool
2. Overflow And Its Signatures
   - Mission: Circuit Breaking With Connection Pool Limits Lab
3. Scope, Verification And Retry Amplification
   - Mission: Calm The Retry Storm Lab
4. Wrap-Up: Mission Debrief

### Outlier Detection And Endpoint Ejection

3 parts and 2 missions:

1. Passive Health Checking
2. Ejection Mechanics And Limits
   - Mission: Outlier Detection And Endpoint Ejection Lab
3. Local, Temporary, And Verified
   - Mission: Raise Both Shields Lab
4. Wrap-Up: Mission Debrief

### Locality Load Balancing And Failover

3 parts and 3 missions:

1. Where Locality Comes From
   - Mission: Give Every Ship Its Orbit Lab
2. Preference, Distribute And Failover
   - Mission: Split Signals Between Two Orbits Lab
3. The Health Dependency And Scope
   - Mission: Locality Load Balancing And Failover Lab
4. Wrap-Up: Mission Debrief

### Capstone

The section ends with a capstone lab that uses everything in it: **A Resilient Payment Path Capstone Lab**.

---

<!-- astrona:playground:environment-explain -->
