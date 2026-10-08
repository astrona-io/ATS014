# Outlier Detection And Endpoint Ejection

<!-- astrona:playground -->
> [!NOTE]
> 🧪 **Hands-on playground for this module** — a clean, throwaway machine to explore on. No task, no grading. Folder: `playground/`
>
> ```sh
> astrona run --git ssh://git@github.com/astrona-io/ATS014.git -c sections/section-040/module-03/playground
> astrona destroy ats-014-playground-040-03
> ```

Astronaut, Kubernetes already has a way to take a broken ship (pod) out of a Service: the **readiness probe**. It is a health check the ship answers about itself, like a pilot reporting "all systems green". It works when the pod knows it is broken.

It does nothing about the pod that passes its probe and still answers every real request with a 503. A bad configuration, a dead dependency, a corrupted cache: the pod feels fine, yet a share of your traffic keeps failing.

**Outlier detection** is Istio's answer, and it works differently from anything else in this section. There is no probe at all. The caller's sidecar watches the answers it is **already getting**, notices that one endpoint keeps failing, and stops sending to it for a while. Think of a squadron where one ship keeps dropping signals: the communications officer pulls that damaged ship out of formation for a while and sends signals to the others.

## How this module is organised

1. **[Passive Health Checking](./course-01-passive-health-checking.md)** — what "passive" means, the fields that define a failing endpoint, and why this is a different kind of check from a readiness probe.
2. **[Ejection Mechanics And Limits](./course-02-ejection-mechanics-and-limits.md)** — when an ejection happens, how long it lasts, why repeat offenders stay out longer, which errors count, and the two safety limits that stop the mesh ejecting everything.
3. **[Local, Temporary, And Verified](./course-03-local-temporary-and-verified.md)** — why every proxy reaches its own verdict, what Kubernetes thinks meanwhile, the counters that prove an ejection, both halves of circuit breaking in one rule, and why locality failover depends on all of this.

The playground also holds an exam-style drill that combines this module with the connection pool from [module 2](../module-02/course.md): [practice task](./playground/docs/practice.md).

## Learning objectives

After this module you can:

- Explain what passive health checking is and how it differs from a readiness probe.
- Configure `trafficPolicy.outlierDetection` with `consecutive5xxErrors`, `interval`, `baseEjectionTime` and `maxEjectionPercent`.
- Choose between `consecutive5xxErrors` and `consecutiveGatewayErrors`, and state that `consecutive5xxErrors` defaults to 5 as soon as an `outlierDetection` block exists.
- Explain why `maxEjectionPercent` at its 10% default prevents any ejection on a small service.
- Predict how long an endpoint stays ejected, including after repeated ejections.
- Show an active ejection from a proxy's statistics and from `istioctl proxy-config endpoints`, and explain why `kubectl get endpoints` disagrees.
- State why locality failover depends on this module.

## Before you start

This module assumes [section 000](../../section-000/module-01/course.md): a proxy (the communications officer) runs beside every pod, `istiod` (mission control) sends it its settings, and `istioctl proxy-config` shows what a proxy really holds.

You need `DestinationRule` and `trafficPolicy` from section 030. This module adds a key beside module 2's `connectionPool`. Istio's documentation groups the two together as "circuit breaking", and they are often set up together.

The playground gives you a training solar system: a `kind` cluster with **Istio 1.30.5** installed with Helm (`istio-base` and `istiod`, no gateways). Namespace **`bookinfo`** is labelled for sidecar injection, and access logs are switched on for the whole mesh. It holds:

- `httpbin` — a small test server. Two healthy pods (`httpbin-v1` and `httpbin-v2`) sit behind one Service on port `8000`.
- `curl` — a client pod. Its sidecar is set up to keep the outlier-detection counters that Part 3 reads.
- `fortio` — a load generator, used in Part 3 and the practice task.

There is **no broken pod yet and no `DestinationRule`**. Part 1 adds the broken pod, so you see the problem before you fix it.

Paste these helpers into your terminal once per session. The parts below use them.

```sh
# 15 single requests from curl to httpbin, counted by status code
count_status() { for i in $(seq 1 15); do
  kubectl exec -n bookinfo deploy/curl -- curl -s -o /dev/null -w "%{http_code}\n" http://httpbin:8000/get
done | sort | uniq -c; }
# httpbin endpoints as the curl sidecar sees them, with the OUTLIER CHECK column
show_endpoints() { istioctl proxy-config endpoints deploy/curl -n bookinfo --cluster "outbound|8000||httpbin.bookinfo.svc.cluster.local"; }
# The curl sidecar's outlier-detection counters for httpbin
ejection_stats() { kubectl exec -n bookinfo deploy/curl -c istio-proxy -- \
  pilot-agent request GET stats | grep -E 'httpbin.bookinfo.*outlier_detection.ejections_(active|total|enforced_consecutive_5xx)'; }
# 30 requests to httpbin over N parallel connections, from fortio
load_test() { kubectl exec -n bookinfo deploy/fortio -c fortio -- \
  fortio load -c "$1" -qps 0 -n 30 -loglevel Warning http://httpbin:8000/get 2>&1 | grep -E "^Code"; }
```

The YAML files for this module are in the playground's [`examples/`](./playground/examples/) folder if you cloned the repository. The parts also show each one in full, written to a file before it is applied.

## Where this fits

This module defines what an "unhealthy endpoint" is, and the next module depends on it. Locality failover has no health checker of its own. It re-uses this one, which is why a locality setup without `outlierDetection` never fails over.

It also works well with module 1. Retries can hide the failures from the caller, while the proxy still collects the evidence it needs to eject the bad endpoint.
