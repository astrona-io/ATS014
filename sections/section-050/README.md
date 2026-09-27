# Section 050: Using Fault Injection

Section 040 configured resilience. This section is how you find out whether any of it works.

A timeout you have never seen fire is a guess, and a retry policy you have never watched retry is a guess. Fault injection lets the mesh fabricate the failure — a two-second delay, a 500 that never reaches the upstream — with no change to any application. The service under test cannot tell an injected failure from a real one, which is what makes the result worth anything.

The same feature answers a second question that is harder to test any other way: what does your application actually do when a dependency is down? Usually something less graceful than anyone expects.

**Curriculum item covered:** Using Fault Injection

---

## What You Will Master

- `fault.delay` with `fixedDelay` — a **slow success**, which is what a degraded dependency really looks like.
- `fault.abort` with `httpStatus` — returned immediately, with the upstream never contacted.
- Which `VirtualService` a fault belongs on: the host you want to pretend is broken, enforced in the **caller's** proxy.
- Why an aborted request leaves no trace in the destination's logs or metrics — and the log asymmetry that proves it.
- The **`FI`** response flag, and how it sits alongside `UT`, `UO` and `UH` from section 040.
- `percentage.value` for sampling, and the 100% default when it is omitted.
- Composing `delay` and `abort` on one rule, and the order they apply in.
- Scoping a fault behind a `match` so only your test client is affected — the difference between a test and an outage.
- Why header-scoped faults depend on the intermediate service propagating headers.
- Using injection to drive section 040: a delay above a timeout, an abort against retries, a failure rate against outlier detection.
- Why retries cannot rescue an injected fault, and what that teaches about what retries are for.
- Finding a live or forgotten fault with `istioctl proxy-config routes` and the `FI` flag.

---

## The Learning Path

### 1. Fault Injection With Delays And Aborts
*   **Module Reader:** **[Module 1: Fault Injection With Delays And Aborts](./module-01/course.md)**
    1. [`fault.delay`](./module-01/course-01-fault-delay.md)
    2. [`fault.abort`](./module-01/course-02-fault-abort.md)
    3. [Scoping, Composition And Hazards](./module-01/course-03-scoping-composition-and-hazards.md)
*   **Hands-on Playground:** `sections/section-050/module-01/playground` — a kind cluster with Istio installed and namespace `fault-demo` holding a two-hop chain, `booking-service` calling `notification-service`, with no routing configured.
    ```bash
    astrona run --git ssh://git@github.com/astrona-io/ATS014.git -c sections/section-050/module-01/playground
    ```
*   **Practice Lab Sandbox:** **`sections/section-050/module-01/labs/lab-01`**
*   **Lab Run Command:**
    ```bash
    astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-050/module-01/labs/lab-01
    ```
*   **Hands-on Objective:** Break a dependency on purpose for your own requests only, and use a fabricated delay to make a route timeout fire on demand — while everybody else's traffic stays at 200.

### 2. Section Capstone Challenge
*   **Comprehensive Challenge:** **`sections/section-050/capstone/labs/lab-01` (A Controlled Chaos Experiment)**
*   **Lab Run Command:**
    ```bash
    astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-050/capstone/labs/lab-01
    ```
*   **Hands-on Objective:** Run two independently scoped experiments on one host at once — an abort that a retry policy cannot rescue, and a delay that drives a timeout — and read the `FI` and `UT` flags to tell which mechanism produced each result.

---

The playground is ungraded: it spins up, prepares the environment, and waits. There is no task and no `astrona submit`. Tear it down with `astrona destroy <name>` when you are finished — the name is printed in the module's playground callout.
