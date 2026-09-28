# Ejection Mechanics And Limits

> Prerequisite: [Passive Health Checking](./course-01-passive-health-checking.md). Next: [Local, Temporary, And Verified](./course-03-local-temporary-and-verified.md).

Marking an endpoint is half the story. This part covers what happens next: when the decision is acted on, how long it lasts, what happens to a repeat offender, and the two limits that exist to stop the mechanism destroying the service it is protecting.

## The timeline

```text
  t=0     failures begin accumulating on endpoint B
          (each success resets B's counter to zero)
            │
            │  consecutive5xxErrors: 3 reached
            ▼
  interval boundary (every `interval`, default 10s)
          ANALYSIS RUNS  →  B is ejected
            │
            ├──── baseEjectionTime: 30s ────┤
            │                               │
            ▼                               ▼
     B receives no traffic            B returns to the pool
                                             │
                                      still broken? 3 more failures
                                             ▼
                                      ejected again — for 2 × 30s
```

Three things to take from that.

**Ejection happens at an interval boundary, not at the instant of the third failure.** `interval` is how often the analysis sweep runs. So expect up to one interval of lag between "the threshold was met" and "traffic stopped". With `interval: 5s` that is invisible; with the default `10s` and a low-traffic service it can look like the policy is not working when it simply has not swept yet.

**`baseEjectionTime` is a floor, not a fixed duration.** The actual ejection time is `baseEjectionTime × (number of times this endpoint has been ejected)`. A second ejection lasts twice as long, a third three times. That is a back-off: an endpoint that keeps coming back broken is tried less and less often, without ever being written off permanently.

**Ejection always expires.** There is no permanent removal. After the time elapses the endpoint is returned to the load balancing set and given traffic again. If it is still broken it fails again and is re-ejected, for longer.

The practical consequence, and the thing that confuses people watching a permanently broken pod: you do **not** see a clean steady state. You see a repeating pattern of brief failure bursts separated by lengthening quiet periods.

## The two safety limits

Both exist for the same reason: a mechanism that removes unhealthy endpoints must not be able to remove *all* of them. If a shared dependency fails, every endpoint starts returning 5xx at once, and an unconstrained detector would eject the entire service — turning a degraded service into a completely unavailable one.

**`maxEjectionPercent`** caps how much of the pool may be ejected at any moment.

> Its default is **10%**.

That default is the single most common reason a correct-looking policy does nothing. 10% of two endpoints, rounded down, is zero endpoints. 10% of three is zero. On any small service the policy runs, counts the failures faithfully, and never ejects anything — silently.

For a two-endpoint service like the playground you must raise it. `100` means "eject as many as are failing", which is right when you would rather have no endpoints than bad ones (and are relying on retries or another locality to cover). A production value is a judgement call: high enough to act, low enough that a correlated failure cannot empty the pool.

**`minHealthPercent`** approaches the same problem from the other side: below this share of healthy hosts, ejection is **disabled entirely**. Set `minHealthPercent: 60` on a two-endpoint service and ejecting one would leave 50% healthy — below the floor — so nothing is ejected at all. It is a useful protection on a large pool and a foot-gun on a small one.

> [!TIP]
> **Try it — the 10% default in action**
>
> ```sh
> kubectl -n outlier-demo patch destinationrule httpbin --type merge -p '
> spec:
>   trafficPolicy:
>     outlierDetection:
>       consecutive5xxErrors: 3
>       interval: 5s
>       baseEjectionTime: 30s
>       maxEjectionPercent: 10'
> sleep 3
> kubectl -n outlier-demo exec deploy/tester -- sh -c \
>   'for i in $(seq 1 60); do curl -s -o /dev/null -w "%{http_code} " http://httpbin:8000/get; done; echo' | tr ' ' '\n' | sort | uniq -c
> kubectl -n outlier-demo exec deploy/tester -c istio-proxy -- \
>   pilot-agent request GET stats | grep 'httpbin.*ejections_active'
> ```
>
> Expect something like:
>
> ```text
>   31 200
>   29 503
> cluster.outbound|8000||httpbin.outlier-demo.svc.cluster.local.outlier_detection.ejections_active: 0
> ```
>
> Roughly half the requests still fail and `ejections_active` is `0`. The failures were counted, the threshold was met, and nothing could be ejected because 10% of two endpoints is zero. Put `maxEjectionPercent: 100` back and run the same loop to see the difference.

## Choosing the numbers

A short guide, since tasks tend to specify behaviour rather than values:

| Requirement | Field to move |
| --- | --- |
| "react faster" | lower `interval` — but remember detection still needs the consecutive failures |
| "tolerate a brief blip" | raise `consecutive5xxErrors` |
| "do not count application errors" | use `consecutiveGatewayErrors` instead of `consecutive5xxErrors` |
| "keep a bad pod out longer each time" | that is automatic — `baseEjectionTime` is multiplied |
| "it must actually eject on a small service" | raise `maxEjectionPercent` above the 10% default |
| "never remove more than half the pool" | `maxEjectionPercent: 50` |
| "stop ejecting if the service is mostly down" | `minHealthPercent` |

> *`maxEjectionPercent` defaults to 10%, which on a two- or three-endpoint service means nothing can ever be ejected.*

## Reference

- [OutlierDetection API](https://istio.io/latest/docs/reference/config/networking/destination-rule/#OutlierDetection) — every field with its default, including the 10% one.
- [Envoy outlier detection](https://www.envoyproxy.io/docs/envoy/latest/intro/arch_overview/upstream/outlier) — the ejection-time multiplication and the enforcing percentages.
- [Circuit breaking task](https://istio.io/latest/docs/tasks/traffic-management/circuit-breaking/) — the upstream walkthrough.
- `pilot-agent request GET stats | grep outlier` — the counters Part 3 uses to prove all of this.
