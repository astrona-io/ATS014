# Configuring Traffic Shifting

Astronaut, this section is about launching a new ship class into a fleet that is already flying. Releasing a new version is a traffic problem before it is a deployment problem. The spaceships (pods) are easy to launch; the hard questions are how many real signals (requests) reach them, and how fast you can change your mind.

Istio gives two answers and this section covers both. Weighted routing moves a controllable percentage of live traffic to the new version — like sending a small share of signals to the new ship class before the whole fleet switches. Real users, real responses, reversible in one apply. Mirroring sends the new version a *copy* of production traffic and throws the answer away — a test ship that hears every signal while nobody listens to its replies. It sees real load while no user is exposed to it. They solve the same problem from opposite ends, and choosing between them is a real decision: weights give you the candidate's answers, mirroring gives you its behaviour under load with no way to compare output.

**Curriculum item covered:** Configuring Traffic Shifting

---

## What You Will Master

- Several weighted destinations in one `route` block, with `weight` beside `destination`, written to add up to 100 (on Istio 1.30.5 other totals are accepted and used as a ratio).
- How a weight becomes a per-request draw inside Envoy, and why cluster selection happens before endpoint load balancing.
- Running a canary as a sequence of applies, and rolling back in one — the reason the feature is worth the configuration.
- Why a merge patch on any list-valued field replaces the list rather than editing it.
- Measuring a statistical split honestly: what 10, 100 and 1000 samples can each tell you.
- Why traffic share and replica count are independent — the section's most testable idea.
- `mirror` as a sibling of `route`, a single destination whose response *and latency* are discarded.
- Why a mirror is never part of the weighted split, and that a full mirror doubles internal request volume.
- `mirrorPercentage` for sampling, and that omitting it means 100%, not 0%.
- Why the receiving proxy's access log is the only proof a mirror works, and what happened to the `-shadow` authority suffix older material describes.
- The three-state mirror diagnostic: policy absent, policy present but no endpoints, or working.
- That the mesh discards the mirrored response but not the work the shadow did — and what that means before mirroring anything with side effects.
- Reading `weightedClusters` and `requestMirrorPolicies` out of a live proxy.

---

## Modules In This Section

Work through the modules in this order. Each part teaches one idea. A mission (a graded lab) comes right after the part it practises, and the last page of each module is a wrap-up. The capstone at the end uses everything in the section at once.

### [Shift Traffic With Weighted Routing](module-01/course.md)

3 parts and 2 missions:

1. [Weighted Destinations](module-01/course-01-weighted-destinations.md)
   - Mission: [Split The Scout Three Ways Lab](module-01/labs/lab-02/question.md)
2. [Running A Rollout](module-01/course-02-running-a-rollout.md)
3. [Weight Versus Replicas, And Proof](module-01/course-03-weight-versus-replicas-and-proof.md)
   - Mission: [Shift Traffic With Weighted Routing Lab](module-01/labs/lab-01/question.md)
4. [Wrap-Up: Mission Debrief](module-01/course-04-wrap-up.md)

### [Mirror Live Traffic To A Shadow Service](module-02/course.md)

3 parts and 2 missions:

1. [Mirror As A Sibling Of Route](module-02/course-01-mirror-as-a-sibling-of-route.md)
2. [Identifying And Sampling Shadow Traffic](module-02/course-02-identifying-and-sampling-shadow-traffic.md)
   - Mission: [Mirror Live Traffic To A Shadow Service Lab](module-02/labs/lab-01/question.md)
3. [Consequences, Verification And Limits](module-02/course-03-consequences-verification-and-limits.md)
   - Mission: [Find The Quiet Shadow Lab](module-02/labs/lab-02/question.md)
4. [Wrap-Up: Mission Debrief](module-02/course-04-wrap-up.md)

### Capstone

Your final mission for this section: **[Canary And Shadow At The Same Time Capstone Lab](capstone/labs/lab-01/README.md)**.

---

<!-- astrona:playground:environment-explain -->