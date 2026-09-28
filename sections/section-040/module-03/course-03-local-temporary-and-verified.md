# Local, Temporary, And Verified

> Prerequisite: [Ejection Mechanics And Limits](./course-02-ejection-mechanics-and-limits.md). Next: [the module landing page](./course.md).

Two properties remain, and both surprise people because they follow from *where* the mechanism lives rather than from what it does. Then the commands that prove an ejection, and the reason the next module depends on all of this.

## The verdict is per proxy

Outlier detection runs inside each client's sidecar, over the responses **that sidecar** received. There is no shared state, no gossip, and no central decision.

```text
   caller A sidecar   ──► has seen B fail 3 times  ──► B ejected from A's pool
   caller C sidecar   ──► has seen B fail once     ──► B still in C's pool
   caller D (no sidecar) ─────────────────────────► talks to B normally
```

So at any moment different callers can hold different opinions about the same endpoint, and all of them are correct — each is a statement about that caller's own experience.

Three consequences:

- **The pod stays in the Service.** `kubectl get endpoints` still lists it. Nothing about the Kubernetes object changes.
- **A workload without a sidecar is unaffected**, because there is no proxy holding a verdict.
- **A low-traffic caller may never eject anything**, simply because it has not accumulated the evidence.

This is the sharpest contrast with a readiness probe, which removes the pod from the Service for everybody, once, centrally.

> [!TIP]
> **Try it — Kubernetes and the proxy disagree**
>
> ```sh
> kubectl -n outlier-demo exec deploy/tester -- sh -c \
>   'for i in $(seq 1 60); do curl -s -o /dev/null http://httpbin:8000/get; done'
> kubectl -n outlier-demo get endpoints httpbin
> istioctl proxy-config endpoints deploy/tester -n outlier-demo \
>   --cluster "outbound|8000||httpbin.outlier-demo.svc.cluster.local"
> ```
>
> Expect something like:
>
> ```text
> NAME      ENDPOINTS                            AGE
> httpbin   10.244.0.14:8080,10.244.0.15:8080    12m
> ENDPOINT             STATUS      OUTLIER CHECK     CLUSTER
> 10.244.0.14:8080     HEALTHY     OK                outbound|8000||httpbin...
> 10.244.0.15:8080     HEALTHY     FAILED            outbound|8000||httpbin...
> ```
>
> Read the last two columns separately. `STATUS: HEALTHY` is what the control plane says — the pod is a ready Service endpoint. `OUTLIER CHECK: FAILED` is **this proxy's own verdict**. The disagreement between those two columns *is* outlier detection, and `kubectl get endpoints` will never show it.

## The counters

Behaviour improving is suggestive; counters are proof. The three to know:

| Counter | Meaning |
| --- | --- |
| `outlier_detection.ejections_active` | endpoints currently ejected (a gauge) |
| `outlier_detection.ejections_total` | lifetime ejections for this cluster |
| `outlier_detection.ejections_enforced_consecutive_5xx` | which rule did the ejecting |

> [!TIP]
> **Try it — the ejection counters**
>
> ```sh
> kubectl -n outlier-demo exec deploy/tester -c istio-proxy -- \
>   pilot-agent request GET stats | grep -E 'httpbin.*outlier_detection.ejections_(active|total|enforced_consecutive_5xx)'
> ```
>
> Expect something like:
>
> ```text
> cluster.outbound|8000||httpbin...outlier_detection.ejections_active: 1
> cluster.outbound|8000||httpbin...outlier_detection.ejections_enforced_consecutive_5xx: 1
> cluster.outbound|8000||httpbin...outlier_detection.ejections_total: 1
> ```
>
> `ejections_active: 1` while the bad endpoint is out, and `enforced_consecutive_5xx` naming *which* rule fired — useful when several thresholds are configured. If `total` is climbing while `active` reads 0, you have caught the endpoint between ejections, which is the next section.

## Watching the cycle

Because ejection expires and the endpoint is retried, a permanently broken pod produces a cycle rather than a steady state. Watching `ejections_total` climb while `ejections_active` flickers is that cycle made visible, and it is worth seeing once so you do not mistake it for instability.

> [!TIP]
> **Try it — the endpoint comes back, and goes again**
>
> ```sh
> for i in 1 2 3 4 5 6; do
>   A=$(kubectl -n outlier-demo exec deploy/tester -c istio-proxy -- \
>     pilot-agent request GET stats 2>/dev/null | grep 'httpbin.*ejections_active' | awk -F': ' '{print $2}')
>   T=$(kubectl -n outlier-demo exec deploy/tester -c istio-proxy -- \
>     pilot-agent request GET stats 2>/dev/null | grep 'httpbin.*ejections_total' | awk -F': ' '{print $2}')
>   echo "active=$A total=$T"
>   kubectl -n outlier-demo exec deploy/tester -- sh -c \
>     'for i in $(seq 1 20); do curl -s -o /dev/null http://httpbin:8000/get; done' 2>/dev/null
> done
> ```
>
> Expect something like:
>
> ```text
> active=1 total=1
> active=1 total=1
> active=0 total=1
> active=1 total=2
> active=1 total=2
> active=1 total=2
> ```
>
> `total` only ever climbs; `active` drops to 0 when `baseEjectionTime` expires and returns to 1 once the re-admitted endpoint fails again. Note the quiet periods get longer as the multiplier grows — the back-off from Part 2, visible.

## Where this fits

Two connections to the rest of the section, both worth being able to state.

**Locality failover depends on this.** The next module's `localityLbSetting` decides where traffic goes when a locality has no healthy endpoints — and "healthy" in a sidecar mesh means "not ejected by outlier detection". There is no separate health checker. A locality failover configuration that omits `outlierDetection` never fails over, because nothing ever marks anything unhealthy. That is the most examinable fact in the next module and it originates here.

**Retries pair well with it.** Ejection needs a few real failures to notice a bad endpoint, and those failures are somebody's requests. Add a retry policy from module 1 and the retried request lands on a different endpoint, so the caller sees a success while the proxy still records the failure it needs. The caller's experience improves and the detection still works — one of the few genuinely free combinations in this section.

## Common pitfalls

> [!WARNING]
> **`maxEjectionPercent` left at its 10% default on a small service.** With two or three endpoints that is zero endpoints and nothing can ever be ejected. The most common reason a correct policy does nothing.
>
> **Not enough traffic.** `consecutive5xxErrors` counts failures in a row *on the same endpoint*, and healthy endpoints dilute the failing one. Twenty requests is usually not enough; sixty usually is.
>
> **Expecting a Kubernetes-level change.** The pod stays in the Service and `kubectl get endpoints` never moves. Use the proxy's stats and `istioctl proxy-config endpoints`.
>
> **Expecting ejection to be permanent.** It lasts `baseEjectionTime × ejection count`, then the endpoint is retried.
>
> **Mistaking the ejection cycle for instability.** A permanently broken pod produces repeating bursts with lengthening gaps. That is the design.
>
> **Assuming one proxy's verdict is shared.** Every client proxy ejects independently based on what it has seen.
>
> **`minHealthPercent` too high on a small pool.** At 60% with two endpoints, ejecting one would breach the floor, so ejection is disabled entirely.
>
> **Expecting detection before any failure.** It is passive. Something has to break first.

> *`STATUS` is what Kubernetes says and `OUTLIER CHECK` is what this proxy decided — the gap between those two columns is the entire feature.*

## Reference

- [OutlierDetection API](https://istio.io/latest/docs/reference/config/networking/destination-rule/#OutlierDetection) — the full schema.
- [Envoy outlier detection statistics](https://www.envoyproxy.io/docs/envoy/latest/intro/arch_overview/upstream/outlier#statistics) — every `ejections_*` counter.
- [Locality load balancing](https://istio.io/latest/docs/tasks/traffic-management/locality-load-balancing/) — the next module, and the dependency this one creates.
- `istioctl proxy-config endpoints <workload> --cluster <name>` — the `OUTLIER CHECK` column, which is the fastest visual check.
