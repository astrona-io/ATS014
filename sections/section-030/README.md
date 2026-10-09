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
- `trafficPolicy` at host, subset and port level: a more specific level overrides only the settings it sets (for example the whole `loadBalancer` block) and inherits the rest.
- Reading `lbPolicy` per cluster from `istioctl proxy-config cluster` to prove a subset override took effect.

---

## Modules In This Section

Work through the modules in this order. Each part teaches one idea. A graded lab comes right after the part it practises, and the last page of each module is a summary. The capstone lab at the end uses everything in the section at once.

### Load Balancer Policy And Session Affinity

5 parts and 3 labs:

1. Choose A Simple Load Balancing Algorithm
   - Lab: Spread Requests Evenly With ROUND_ROBIN Lab
2. Pin Requests To A Pod With `consistentHash`
3. Hash A Cookie, The Source IP Or A Query Parameter
4. Set A Load Balancer Per Subset
   - Lab: Pin A Subset By Header And Override Another Subset Lab
5. Set A Load Balancer Per Port
   - Lab: Issue A Sticky Cookie On One Port Lab
6. Summary

### Capstone

The section ends with a capstone lab that uses everything in it: **Combine Session Affinity With Traffic Mirroring Capstone Lab**.

---

<!-- astrona:playground:environment-explain -->