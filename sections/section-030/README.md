# Defining Traffic Policies With Destination Rules

Astronaut, your flight plan (the `VirtualService`) now gets every signal to the right beacon. But a beacon is a call sign that a whole squadron of spaceships (pods) answers to, and each signal still has to land on just one ship. Picking that ship is this section's mission. Later sections add two more questions: how many channels to hold open to a ship, and when a ship has misbehaved enough to be pulled out of formation. All of those are `DestinationRule` decisions, made by the communications officer on the *calling* ship, and they live under one field: `trafficPolicy`.

This section covers the endpoint-selection half of that field, and the precedence rules that govern every other key in it. The resilience half (connection pools, outlier detection and locality) uses the same object with different keys.

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

## Modules In This Section

Work through the modules in this order. Each part teaches one idea. A mission (a graded lab) comes right after the part it practises, and the last page of each module is a wrap-up. The capstone at the end uses everything in the section at once.

### [Load Balancer Policy And Session Affinity](module-01/course.md)

4 parts and 3 missions:

1. [Endpoint Selection And The `simple` Algorithms](module-01/course-01-endpoint-selection-and-simple-algorithms.md)
   - Mission: [Spread The Signals Evenly Lab](module-01/labs/lab-03/question.md)
2. [`consistentHash` And The Ring](module-01/course-02-consistent-hash-and-the-ring.md)
3. [Sticky Cookies And Other Hash Sources](module-01/course-03-sticky-cookies-and-other-hash-sources.md)
4. [Policy Levels And Verification](module-01/course-04-policy-levels-and-verification.md)
   - Mission: [Load Balancer Policy And Session Affinity Lab](module-01/labs/lab-01/question.md)
   - Mission: [Session Affinity For Browsers Lab](module-01/labs/lab-02/question.md)
5. [Wrap-Up: Mission Debrief](module-01/course-05-wrap-up.md)

### Capstone

Your final mission for this section: **[Sticky Sessions With A Shadowed Canary Capstone Lab](capstone/labs/lab-01/README.md)**.

---

<!-- astrona:playground:environment-explain -->