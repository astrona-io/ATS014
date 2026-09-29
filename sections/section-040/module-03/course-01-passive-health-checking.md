# Passive Health Checking

> Prerequisite: [the module landing page](./course.md). Next: [Ejection Mechanics And Limits](./course-02-ejection-mechanics-and-limits.md).

This part establishes what the mechanism is, what it watches, and why it catches a class of failure that Kubernetes structurally cannot.

## The problem, made visible

With two endpoints and no policy, load balancing sends roughly half the traffic into the failing pod.

> [!TIP]
> **Try it — a Service with one poisoned endpoint**
>
> ```sh
> kubectl -n outlier-demo get endpoints httpbin
> kubectl -n outlier-demo get pods -o wide
> kubectl -n outlier-demo exec deploy/tester -- sh -c \
>   'for i in $(seq 1 20); do curl -s -o /dev/null -w "%{http_code} " http://httpbin:8000/get; done; echo'
> ```
>
> Expect something like:
>
> ```text
> NAME      ENDPOINTS                            AGE
> httpbin   10.244.0.14:8080,10.244.0.15:8080    5m
> httpbin-bad-...    1/1 Running   10.244.0.15
> httpbin-good-...   1/1 Running   10.244.0.14
> 200 503 200 503 503 200 200 503 200 503 200 503 200 200 503 200 503 200 503 200
> ```
>
> Both endpoints are listed and **both pods show `1/1` Running**. Kubernetes considers them equally healthy. Half the calls fail anyway. Note the bad pod's IP — you will want it in Part 3.

## Active versus passive

The distinction is worth stating precisely, because it is the shape of the whole module.

| | Readiness probe (Kubernetes) | Outlier detection (Istio) |
| --- | --- | --- |
| Kind | **active** — synthetic requests on a schedule | **passive** — observes real traffic |
| Who decides | the kubelet, per pod | each client proxy, independently |
| What it asks | "do you say you are ready?" | "have your answers to *me* been failing?" |
| Effect | removes the pod from the Service, for everyone | removes the endpoint from **one proxy's** load balancing set |
| Catches | a pod that knows it is broken | a pod that does not know, or lies |

The second row is the one people underestimate and Part 3 returns to. The fifth row is why this module exists: a probe is a question the pod answers about itself, and a pod with a dead downstream dependency or a poisoned cache will answer it correctly and still fail every real request.

Passive checking has a cost that follows from its nature: **it needs real failures to notice anything.** The evidence is other people's failed requests. There is no way to detect a bad endpoint before it has broken something.

## The fields

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: httpbin
  namespace: outlier-demo
spec:
  host: httpbin
  trafficPolicy:
    outlierDetection:
      consecutive5xxErrors: 3
      interval: 5s
      baseEjectionTime: 30s
      maxEjectionPercent: 100
```

The detection fields — the ones that define what counts as an outlier:

- **`consecutive5xxErrors`** — how many 5xx responses **in a row from the same endpoint** mark it. *Consecutive* is the operative word: a single success resets that endpoint's counter to zero.
- **`consecutiveGatewayErrors`** — the same idea restricted to 502/503/504, for when you do not want application 500s to count.
- **`consecutiveLocalOriginFailures`** — counts failures the proxy itself observed (connection refused, reset) rather than status codes, used with `splitExternalLocalOriginErrors`.

The remaining fields — `interval`, `baseEjectionTime`, `maxEjectionPercent`, `minHealthPercent` — govern what *happens* once an endpoint is marked, and they are Part 2.

## Why "consecutive" and "per endpoint" matter together

Both words do real work, and together they explain why a test that seems generous is not.

Counting is **per endpoint**: each endpoint has its own counter. And it is **consecutive**: any success resets it.

Now consider the playground. Load balancing spreads requests across two endpoints, so the bad one receives roughly every other request. To accumulate three consecutive failures it must be chosen three times in a row — and with round-robin-ish selection that takes a while. Twenty requests is usually not enough. Sixty usually is.

The general shape: **the traffic needed to trigger an ejection grows with the number of healthy endpoints**, because they dilute the failing one. On a service with ten endpoints and one bad one, `consecutive5xxErrors: 3` may take hundreds of requests. That is an argument for `consecutiveGatewayErrors` tuned low, or for accepting that detection is not instant.

> [!TIP]
> **Try it — apply the detection and drive enough traffic to trigger it**
>
> ```sh
> kubectl apply -f - <<'EOF'
> apiVersion: networking.istio.io/v1
> kind: DestinationRule
> metadata:
>   name: httpbin
>   namespace: outlier-demo
> spec:
>   host: httpbin
>   trafficPolicy:
>     outlierDetection:
>       consecutive5xxErrors: 3
>       interval: 5s
>       baseEjectionTime: 30s
>       maxEjectionPercent: 100
> EOF
> kubectl -n outlier-demo exec deploy/tester -- sh -c \
>   'for i in $(seq 1 60); do curl -s -o /dev/null -w "%{http_code} " http://httpbin:8000/get; done; echo'
> ```
>
> Expect something like:
>
> ```text
> 200 503 503 200 503 503 503 200 200 503 200 200 200 200 200 200 200 200 200 200 ...
> ```
>
> The 503s cluster near the beginning and then stop. That transition is the ejection: once the bad endpoint accumulated three consecutive failures and the next analysis interval came round, the client proxy removed it from its own pool. Sixty requests is deliberate — with load balancing diluting the failures, fewer often will not get there.

## Common pitfalls

> [!WARNING]
> **Expecting it to catch a bad endpoint before it breaks anything.** Passive means it learns from real failed requests. There is no pre-emptive detection.
>
> **Assuming an ejection is mesh-wide.** Each client proxy decides independently, from its own traffic. One caller can be avoiding an endpoint that another is still using happily.
>
> **Treating it as a replacement for readiness probes.** They answer different questions. A probe removes a pod from the Service for everyone; an ejection removes an endpoint from one proxy's load balancing set.
>
> **Expecting `1/1 Running` to mean a pod is serving correctly.** That is exactly the case this module exists for.
>
> **Configuring it on a Service with one endpoint.** `maxEjectionPercent` and simple arithmetic mean there is usually nothing it can safely eject.

> *Passive means the evidence is other people's failed requests — nothing is detected until something has already broken.*

## Reference

- [Circuit breaking task](https://istio.io/latest/docs/tasks/traffic-management/circuit-breaking/) — Istio groups outlier detection under this heading.
- [OutlierDetection API](https://istio.io/latest/docs/reference/config/networking/destination-rule/#OutlierDetection) — every field, including the local-origin variants.
- [Envoy outlier detection](https://www.envoyproxy.io/docs/envoy/latest/intro/arch_overview/upstream/outlier) — the algorithm, the counters, and the exact meaning of each threshold.
- [Kubernetes readiness probes](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/#container-probes) — the active mechanism this one complements rather than replaces.
