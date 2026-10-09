# Using Fault Injection

Astronaut, your ships can carry resilience settings: abort windows (timeouts), re-sent signals (retries) and shields (circuit breakers). This section is your simulation drill. It is how you find out whether any of it works.

A timeout you have never seen fire is a guess. A retry policy you have never watched retry is a guess. Fault injection lets the mesh fake the failure: a two-second delay, or a 500 that never reaches the ship it was meant for. No application changes. The service under test cannot tell a fake failure from a real one, and that is what makes the result worth anything.

The same feature answers a second question that is hard to test any other way: what does your crew actually do when a ship they depend on goes dark? Usually something less graceful than anyone expects.

**Curriculum item covered:** Using Fault Injection

---

## What You Will Master

- `fault.delay` with `fixedDelay` — a **slow success**, which is what a degraded dependency really looks like.
- `fault.abort` with `httpStatus` — returned immediately, with the upstream never contacted.
- Which `VirtualService` a fault belongs on: the host you want to pretend is broken, enforced in the **caller's** proxy.
- Why an aborted request leaves no trace in the destination's logs or metrics — and the log asymmetry that proves it.
- The **`FI`** response flag, and how it sits alongside `UT` (timeout), `UO` (overflow) and `UH` (no healthy ship).
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

### [Fault Injection With Delays And Aborts](module-01/course.md)

4 parts and 3 missions:

1. [Slow A Ship Down](module-01/course-01-slow-a-ship-down.md)
2. [Fail A Signal Before It Leaves](module-01/course-02-fail-a-signal-before-it-leaves.md)
   - Mission: [Run Two Simulation Drills Lab](module-01/labs/lab-02/question.md)
3. [Scope A Drill To Your Own Signals](module-01/course-03-scope-a-drill-to-your-own-signals.md)
   - Mission: [Stop The Drill That Never Ended Lab](module-01/labs/lab-03/question.md)
4. [Drive Your Resilience Settings With Faults](module-01/course-04-drive-your-resilience-settings-with-faults.md)
   - Mission: [Fault Injection With Delays And Aborts Lab](module-01/labs/lab-01/question.md)
5. [Wrap-Up: Mission Debrief](module-01/course-05-wrap-up.md)

### Capstone

Your final mission for this section: **[A Controlled Chaos Experiment Capstone Lab](capstone/labs/lab-01/README.md)**.

---

<!-- astrona:playground:environment-explain -->
