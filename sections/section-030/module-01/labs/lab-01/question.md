# Question

Solve this question on: `terminal`

Namespace `lb-demo` runs two versions of `httpbin` behind one Service:

* `httpbin-stable` — **3 replicas**, pods labelled `version: stable`
* `httpbin-canary` — **2 replicas**, pods labelled `version: canary`
* `httpbin` — one Service on port 8000 selecting on `app` only
* `tester` — a client pod with `curl`

Istio is installed, every pod is injected, and there is no [`DestinationRule`](https://istio.io/latest/docs/reference/config/networking/destination-rule/) and no [`VirtualService`](https://istio.io/latest/docs/reference/config/networking/virtual-service/).

The stable version holds per-user state in memory, so its users must keep reaching the same pod. The canary holds no state and should simply be spread evenly while it is being load tested.

1.  A `DestinationRule` named `httpbin` for host `httpbin`, defining exactly two subsets: **`stable`** (`version: stable`) and **`canary`** (`version: canary`).
2.  A **host-level** `trafficPolicy` using **`consistentHash`** on the header **`x-user`**.
3.  A **subset-level** `trafficPolicy` on the **`canary`** subset only, using **`simple: ROUND_ROBIN`**, overriding the host-level policy for that subset.
4.  A `VirtualService` named `httpbin` for host `httpbin` with two `http` rules, in this order:
    *   requests carrying the header **`x-track: canary`** go to subset **`canary`**
    *   everything else goes to subset **`stable`**

**What the grader checks**

5.  Twelve requests carrying the same `x-user` value and no `x-track` header all reach **one single endpoint** — the affinity is real.
6.  Twelve requests carrying `x-track: canary` **and** the same `x-user` value reach **more than one endpoint** — the subset override beat the host policy.
7.  Twelve requests with **no** `x-user` header and no `x-track` reach more than one endpoint, because a request with nothing to hash falls back to normal load balancing.
8.  The proxy's cluster dump shows **different `lbPolicy` values** for the `stable` and `canary` clusters.
9.  Replica counts are unchanged — `httpbin-stable` still has 3 and `httpbin-canary` still has 2.
10. The `httpbin` Service selector still selects on `app` only.

---

---

## Reference

The official documentation for everything this task touches — open these rather than trying to recall field names:

- [VirtualService API](https://istio.io/latest/docs/reference/config/networking/virtual-service/) — the whole object: `hosts`, `gateways`, and every field an `http` rule can carry
- [DestinationRule API](https://istio.io/latest/docs/reference/config/networking/destination-rule/) — `host`, `subsets`, and the `trafficPolicy` block
- [Subsets and traffic policy](https://istio.io/latest/docs/reference/config/networking/destination-rule/#Subset) — how a subset name maps to pod labels
- [HTTPMatchRequest API](https://istio.io/latest/docs/reference/config/networking/virtual-service/#HTTPMatchRequest) — every match key: `headers`, `uri`, `queryParams`, `method`, `withoutHeaders`
- [StringMatch API](https://istio.io/latest/docs/reference/config/networking/virtual-service/#StringMatch) — the `exact` / `prefix` / `regex` choice and what each means
- [ConsistentHashLB API](https://istio.io/latest/docs/reference/config/networking/destination-rule/#LoadBalancerSettings-ConsistentHashLB) — the four hash sources, `ttl`, and `minimumRingSize`
- [LoadBalancerSettings API](https://istio.io/latest/docs/reference/config/networking/destination-rule/#LoadBalancerSettings) — the `simple` enum and the `consistentHash` alternative
- [Debugging Envoy and istiod](https://istio.io/latest/docs/ops/diagnostic-tools/proxy-cmd/) — `proxy-status`, `proxy-config` and `x describe` in full
- [Istio analyzer messages](https://istio.io/latest/docs/reference/config/analysis/) — every `IST####` code and what triggers it
