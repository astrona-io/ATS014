# Using Fault Injection

Workloads in the mesh can carry resilience settings: timeouts, retries and circuit breaking. Fault injection is how you find out whether any of them work.

A timeout you have never seen fire is a guess. A retry policy you have never watched retry is a guess. Fault injection makes the sidecar proxy fake the failure: a two-second delay, or a `500` returned before the request ever reaches the service. The application does not change. The calling service cannot tell a fake failure from a real one, and that is what makes the test worth anything.

The same feature answers a second question that is hard to test any other way: what does your application actually do when a service it depends on stops responding? Usually something less graceful than anyone expects.

**Curriculum item covered:** Using Fault Injection

---

## What You Will Master

- `fault.delay` with `fixedDelay` — a **slow success**, which is what a degraded dependency really looks like.
- `fault.abort` with `httpStatus` — returned immediately, with the upstream never contacted.
- Which `VirtualService` a fault belongs on: the host you want to pretend is broken, enforced in the **caller's** proxy.
- Why an aborted request leaves no trace in the destination's logs or metrics — and the log asymmetry that proves it.
- The **`FI`** response flag, and how it sits alongside `UT` (timeout), `UO` (overflow) and `UH` (no healthy upstream endpoint).
- `percentage.value` for sampling, and the 100% default when it is omitted.
- Composing `delay` and `abort` on one rule, and the order they apply in.
- Scoping a fault behind a `match` so only your test client is affected — the difference between a test and an outage.
- Why header-scoped faults depend on the intermediate service propagating headers.
- Using injection to test resilience settings: a delay above a timeout, an abort against retries, a failure rate against outlier detection.
- Why retries cannot rescue an injected fault, and what that teaches about what retries are for.
- Finding a live or forgotten fault with `istioctl proxy-config routes` and the `FI` flag.

---

## Modules In This Section

Work through the modules in this order. Each part teaches one idea. A mission (a graded lab) comes right after the part it practises, and the last page of each module is a wrap-up. The capstone at the end uses everything in the section at once.

### Fault Injection With Delays And Aborts

4 parts and 3 missions:

1. Slow A Ship Down
2. Fail A Signal Before It Leaves
   - Mission: Run Two Simulation Drills Lab
3. Scope A Drill To Your Own Signals
   - Mission: Stop The Drill That Never Ended Lab
4. Drive Your Resilience Settings With Faults
   - Mission: Fault Injection With Delays And Aborts Lab
5. Wrap-Up: Mission Debrief

### Capstone

The section ends with a capstone lab that uses everything in it: **A Controlled Chaos Experiment Capstone Lab**.

---

<!-- astrona:playground:environment-explain -->
