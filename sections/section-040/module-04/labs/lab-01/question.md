# Question

Solve this question on: `terminal`

Namespace `locality-demo` has one Service with two endpoints in two declared localities:

* `httpbin-zone-a` — locality **`local/zone-a`**, 1 replica. **Returns 503 to every request** while passing its readiness probe.
* `httpbin-zone-b` — locality **`local/zone-b`**, 1 replica. Healthy.
* `httpbin` — one Service on port 8000 in front of both
* `tester` — a client pod with `curl`, running on a node labelled `local/zone-a`, so **`zone-a` is the caller's own locality**

Istio is installed, every pod is injected, and there is no [`DestinationRule`](https://istio.io/latest/docs/reference/config/networking/destination-rule/).

Because Istio prefers the caller's locality by default, nearly all traffic currently goes to `zone-a` — the broken one — and fails. Make traffic leave that locality.

1.  Create a `DestinationRule` named `httpbin` for host `httpbin`.
2.  Configure **`outlierDetection`** so the failing endpoint can be marked unhealthy:
    *   `consecutive5xxErrors` **2**
    *   `interval` **`5s`**
    *   `baseEjectionTime` **`30s`**
    *   `maxEjectionPercent` at a value that can actually eject one of two endpoints
3.  Configure **`loadBalancer.localityLbSetting`** with `enabled: true`.
4.  Do **not** scale, delete or fix `httpbin-zone-a`, and do not change the Service selector. Traffic must leave the locality because the endpoint was judged unhealthy, not because you removed it.

**What the grader checks**

5.  Both endpoints still exist and both Deployments still run 1 replica.
6.  The `DestinationRule` contains both `outlierDetection` and `localityLbSetting`. A locality setting **without** outlier detection is the failure this task exists to teach: nothing ever marks an endpoint unhealthy, so nothing ever fails over.
7.  `maxEjectionPercent` is high enough to eject one of two endpoints.
8.  Both endpoints report a non-empty locality in the proxy dump.
9.  After driving traffic, the `zone-a` endpoint shows `OUTLIER CHECK: FAILED`, or the ejection counters have moved.
10. Traffic measured afterwards is overwhelmingly successful, having moved to `zone-b`.

---

---

## Reference

The official documentation for everything this task touches — open these rather than trying to recall field names:

- [DestinationRule API](https://istio.io/latest/docs/reference/config/networking/destination-rule/) — `host`, `subsets`, and the `trafficPolicy` block
- [Subsets and traffic policy](https://istio.io/latest/docs/reference/config/networking/destination-rule/#Subset) — how a subset name maps to pod labels
- [OutlierDetection API](https://istio.io/latest/docs/reference/config/networking/destination-rule/#OutlierDetection) — `consecutive5xxErrors`, `interval`, `baseEjectionTime`, `maxEjectionPercent`
- [ConsistentHashLB API](https://istio.io/latest/docs/reference/config/networking/destination-rule/#LoadBalancerSettings-ConsistentHashLB) — the four hash sources, `ttl`, and `minimumRingSize`
- [LoadBalancerSettings API](https://istio.io/latest/docs/reference/config/networking/destination-rule/#LoadBalancerSettings) — the `simple` enum and the `consistentHash` alternative
- [LocalityLoadBalancerSetting API](https://istio.io/latest/docs/reference/config/networking/destination-rule/#LocalityLoadBalancerSetting) — `distribute`, `failover` and the health dependency
- [Debugging Envoy and istiod](https://istio.io/latest/docs/ops/diagnostic-tools/proxy-cmd/) — `proxy-status`, `proxy-config` and `x describe` in full
