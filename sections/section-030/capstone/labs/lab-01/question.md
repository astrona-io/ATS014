# Question

Solve this question on: `terminal`

Namespace `sessions` runs two versions of `httpbin` behind one Service:

* `httpbin-stable` — **3 replicas**, pods labelled `version: stable`. Holds per-user state in memory.
* `httpbin-canary` — **2 replicas**, pods labelled `version: canary`. Holds no state.
* `httpbin` — one Service on port 8000 selecting on `app` only
* `tester` — a client pod with `curl`

Istio is installed, every pod is injected, and there is no [`DestinationRule`](https://istio.io/latest/docs/reference/config/networking/destination-rule/) and no [`VirtualService`](https://istio.io/latest/docs/reference/config/networking/virtual-service/).

The canary is not ready for users, but it needs realistic load. Deliver a configuration where every user keeps reaching the same stable pod, while the canary quietly receives a copy of everything.

**Destination policy**

1.  A `DestinationRule` named `httpbin` for host `httpbin`, defining exactly two subsets: **`stable`** (`version: stable`) and **`canary`** (`version: canary`).
2.  A **host-level** `trafficPolicy` using **`consistentHash`** on the header **`x-session`**.
3.  A **subset-level** `trafficPolicy` on the **`canary`** subset only, using **`simple: LEAST_REQUEST`**. The canary is being load tested, so it must spread rather than pin.
4.  The `stable` subset must carry **no** `trafficPolicy` of its own — it inherits the host-level one.

**Routing**

5.  A `VirtualService` named `httpbin` for host `httpbin` with exactly **one** `http` rule.
6.  That rule routes **100% of caller traffic to subset `stable`**.
7.  The same rule **mirrors** its requests to subset **`canary`**, with `mirrorPercentage` set explicitly to **100**.

**What the grader checks**

8.  Twelve requests carrying the same `x-session` value all reach **one single stable endpoint**.
9.  Twelve requests with **no** `x-session` header reach more than one endpoint — nothing to hash means normal load balancing.
10. No caller response comes from a canary pod: the canary must be a mirror target, not a route destination.
11. The canary receives a copy of essentially every request, identifiable by the rewritten `-shadow` authority in its proxy access log.
12. The `stable` and `canary` clusters report **different** `lbPolicy` values in the proxy dump.
13. Replica counts are unchanged (3 and 2), and the Service selector still selects on `app` only.

---

---

## Reference

The official documentation for everything this task touches — open these rather than trying to recall field names:

- [VirtualService API](https://istio.io/latest/docs/reference/config/networking/virtual-service/) — the whole object: `hosts`, `gateways`, and every field an `http` rule can carry
- [DestinationRule API](https://istio.io/latest/docs/reference/config/networking/destination-rule/) — `host`, `subsets`, and the `trafficPolicy` block
- [Subsets and traffic policy](https://istio.io/latest/docs/reference/config/networking/destination-rule/#Subset) — how a subset name maps to pod labels
- [HTTPMirrorPolicy API](https://istio.io/latest/docs/reference/config/networking/virtual-service/#HTTPMirrorPolicy) — `mirror`, `mirrors` and `mirrorPercentage`
- [ConsistentHashLB API](https://istio.io/latest/docs/reference/config/networking/destination-rule/#LoadBalancerSettings-ConsistentHashLB) — the four hash sources, `ttl`, and `minimumRingSize`
- [LoadBalancerSettings API](https://istio.io/latest/docs/reference/config/networking/destination-rule/#LoadBalancerSettings) — the `simple` enum and the `consistentHash` alternative
- [Debugging Envoy and istiod](https://istio.io/latest/docs/ops/diagnostic-tools/proxy-cmd/) — `proxy-status`, `proxy-config` and `x describe` in full
- [Istio analyzer messages](https://istio.io/latest/docs/reference/config/analysis/) — every `IST####` code and what triggers it
