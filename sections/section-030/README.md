# Defining Traffic Policies With Destination Rules

A `VirtualService` picks the host (and maybe the subset) for each request. But a host is usually backed by several pods, and each request still has to go to exactly one of them. Picking that pod, the endpoint, is what this section is about.

Other `DestinationRule` settings answer two more questions: how many connections to keep open to an endpoint, and when an endpoint has failed often enough to be removed for a while. All of these are made by the sidecar proxy of the *calling* pod, and they live under one field: `trafficPolicy`.

This section covers the endpoint-selection half of that field, and the precedence rules that govern every other key in it. The resilience half (connection pools, outlier detection and locality) uses the same object with different keys.

**Curriculum item covered:** Defining Traffic Policies with Destination Rules

---

## What You Will Master

- Where endpoint selection sits in the request path: route match, then cluster selection, then endpoint choice.
- `loadBalancer.simple` and what `ROUND_ROBIN`, `LEAST_REQUEST`, `RANDOM` and `PASSTHROUGH` each do — including why `LEAST_REQUEST` looks slightly uneven.
- `loadBalancer.consistentHash` over a header, a cookie, a query parameter or the source IP.
- The ring-hash mechanism: why no state is stored, and why changing the endpoint set moves only about `1/N` of sessions.
- That session affinity (sending the same client to the same pod every time) is best effort: an optimisation, not a substitute for shared session state.
- The silent fallback: a request with nothing to hash gets ordinary load balancing, with no error.
- Istio generating a session cookie when `httpCookie.ttl` is set, and why leaving `ttl` out is sometimes right.
- `trafficPolicy` at host, subset and port level, and that a more specific one **replaces** rather than merges.
- Reading `lbPolicy` per cluster from `istioctl proxy-config cluster` to prove a subset override took effect.

---

## Modules In This Section

Work through the modules in this order. Each part teaches one idea. A mission (a graded lab) comes right after the part it practises, and the last page of each module is a wrap-up. The capstone at the end uses everything in the section at once.

### Load Balancer Policy And Session Affinity

4 parts and 3 missions:

1. Endpoint Selection And The `simple` Algorithms
   - Mission: Spread The Signals Evenly Lab
2. `consistentHash` And The Ring
3. Sticky Cookies And Other Hash Sources
4. Policy Levels And Verification
   - Mission: Load Balancer Policy And Session Affinity Lab
   - Mission: Session Affinity For Browsers Lab
5. Wrap-Up: Mission Debrief

### Capstone

The section ends with a capstone lab that uses everything in it: **Sticky Sessions With A Shadowed Canary Capstone Lab**.

---

<!-- astrona:playground:environment-explain -->