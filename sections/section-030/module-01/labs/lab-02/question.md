# Question

Solve this question on: `terminal`

Namespace `lb-demo` runs one Service over two versions:

* `httpbin-stable` — 3 replicas, pods labelled `version: stable`
* `httpbin-canary` — 2 replicas, pods labelled `version: canary`
* `httpbin` — one Service on port **8000**, targeting container port 8080, selecting on `app` only
* `tester` — a client pod with `curl`

Istio is installed and every pod is injected. There is no [`DestinationRule`](https://istio.io/latest/docs/reference/config/networking/destination-rule/) and no [`VirtualService`](https://istio.io/latest/docs/reference/config/networking/virtual-service/).

The application keeps per-session state in memory. Its clients are browsers, which arrive with no identifying header — so pinning on a header the client never sends would do nothing.

Configure host `httpbin` in namespace `lb-demo` so that:

1.  A `DestinationRule` named `httpbin` applies its load balancer policy through **`portLevelSettings` for port `8000`** — not as a bare host-level `loadBalancer`.
2.  That policy uses **`consistentHash`** on an **HTTP cookie** named **`session-id`**.
3.  The cookie has a **`ttl`**, so that **Istio issues the cookie itself** to a client that arrives without one. A client that has never been seen before must receive a `Set-Cookie` on its first response.
4.  A client that returns the cookie is **pinned to a single endpoint** across repeated requests.
5.  A client that sends **no** cookie is **not** pinned — those requests spread across endpoints.
6.  Leave the Deployments and the Service unchanged. Do not change replica counts or the Service selector.

One warning from the module, because it is the difference between this working and silently doing nothing: **without `ttl`, Istio only hashes a cookie the client already sends.** It will not create one.

The grader sends live traffic from the `tester` pod, reads the response headers, and compares which endpoints served which requests, so the policy has to work — not merely exist.

---

---

## Reference

The official documentation for everything this task touches — open these rather than trying to recall field names:

- [VirtualService API](https://istio.io/latest/docs/reference/config/networking/virtual-service/) — the whole object: `hosts`, `gateways`, and every field an `http` rule can carry
- [DestinationRule API](https://istio.io/latest/docs/reference/config/networking/destination-rule/) — `host`, `subsets`, and the `trafficPolicy` block
- [Subsets and traffic policy](https://istio.io/latest/docs/reference/config/networking/destination-rule/#Subset) — how a subset name maps to pod labels
- [ConsistentHashLB API](https://istio.io/latest/docs/reference/config/networking/destination-rule/#LoadBalancerSettings-ConsistentHashLB) — the four hash sources, `ttl`, and `minimumRingSize`
- [LoadBalancerSettings API](https://istio.io/latest/docs/reference/config/networking/destination-rule/#LoadBalancerSettings) — the `simple` enum and the `consistentHash` alternative
- [TrafficPolicy portLevelSettings](https://istio.io/latest/docs/reference/config/networking/destination-rule/#TrafficPolicy-PortTrafficPolicy) — attaching policy to one port instead of the whole host
- [Debugging Envoy and istiod](https://istio.io/latest/docs/ops/diagnostic-tools/proxy-cmd/) — `proxy-status`, `proxy-config` and `x describe` in full
