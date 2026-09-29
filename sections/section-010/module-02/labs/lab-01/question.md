# Question

Solve this question on: `terminal`

Three injected namespaces exist, and every proxy currently carries the whole service registry:

* `sidecar-demo` — a `tester` client pod with `curl`, and a `local-backend` Service on port 8000
* `sidecar-other` — an `httpbin` Service on port 8000
* `sidecar-third` — an `httpbin` Service on port 8000

There is no [`Sidecar`](https://istio.io/latest/docs/reference/config/networking/sidecar/) resource anywhere. From `tester`, all three backends are currently reachable.

The mesh runs with `outboundTrafficPolicy: REGISTRY_ONLY`, so a destination the proxy no longer carries is genuinely unreachable rather than quietly passed through.

The platform team wants `sidecar-demo` to be told about only what it actually calls.

1.  Create a `Sidecar` resource named **`default`** in namespace **`sidecar-demo`** that applies to **every workload in that namespace** — do not use a `workloadSelector`.
2.  Scope its `egress` hosts to exactly three things: the proxy's **own namespace**, **`istio-system`**, and **`sidecar-other`**.
3.  `sidecar-third` must **not** be in the proxy's configuration, and must not be reachable from `tester`.
4.  `sidecar-other` must still be reachable from `tester` — an `HTTP 200` from `http://httpbin.sidecar-other:8000/get`.
5.  `local-backend` in the proxy's own namespace must still be reachable.
6.  The proxy's cluster list must be measurably smaller than the unscoped baseline.
7.  Leave the Deployments, Services and namespaces otherwise unchanged. Do not delete `sidecar-third` or its workload to make the check pass — the traffic must be stopped by scoping, not by removing the target.

The grader reads the proxy's own configuration dump *and* sends live traffic, so both the reduction and the reachability have to be real.

---

---

## Reference

The official documentation for everything this task touches — open these rather than trying to recall field names:

- [Sidecar API](https://istio.io/latest/docs/reference/config/networking/sidecar/) — `workloadSelector`, `egress.hosts` and the `<namespace>/<host>` syntax
- [MeshConfig outboundTrafficPolicy](https://istio.io/latest/docs/reference/config/istio.mesh.v1alpha1/#MeshConfig-OutboundTrafficPolicy) — `ALLOW_ANY` versus `REGISTRY_ONLY`
- [Debugging Envoy and istiod](https://istio.io/latest/docs/ops/diagnostic-tools/proxy-cmd/) — `proxy-status`, `proxy-config` and `x describe` in full
