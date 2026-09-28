# Preference, `distribute` And `failover`

> Prerequisite: [Where Locality Comes From](./course-01-where-locality-comes-from.md). Next: [The Health Dependency And Scope](./course-03-the-health-dependency-and-scope.md).

Before writing anything, know what you already have. A surprising share of "locality configurations" in the wild restate the default. This part covers that default, then the two mutually exclusive ways to override it.

## The default: prefer local, spill over when you must

Istio **prefers the caller's own locality by default**, with no `localityLbSetting` anywhere. A client in `zone-a` sends to `zone-a` endpoints while they are available, and spills over when they are not.

The matching is hierarchical and most-specific-first: same region *and* zone *and* subzone beats same region and zone, which beats same region, which beats anything.

```text
   caller in  local/zone-a
        │
        ├─ 1. endpoints in local/zone-a       ← all traffic, while any are healthy
        ├─ 2. endpoints in local/<other zone> ← only when zone-a has none
        └─ 3. endpoints in <other region>     ← only when the region has none
```

So the common requirement — "keep traffic in the zone, fall back if the zone dies" — needs **no configuration at all**. What `localityLbSetting` adds is *control* over that preference: explicit proportions, or an explicit fallback order.

> [!TIP]
> **Try it — the default preference, with nothing configured**
>
> ```sh
> kubectl -n locality-demo get destinationrule
> kubectl -n locality-demo exec deploy/tester -- sh -c \
>   'for i in $(seq 1 20); do curl -s -o /dev/null http://httpbin:8000/get; done'
> kubectl -n locality-demo logs deploy/tester -c istio-proxy --tail=20 \
>   | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:8080' | sort | uniq -c
> ```
>
> Expect something like:
>
> ```text
> No resources found in locality-demo namespace.
>      20 10.244.0.21:8080
> ```
>
> Twenty requests, all to one endpoint — the one sharing the caller's locality — with no `DestinationRule` in the namespace at all. Compare that with an ordinary two-endpoint service, which would split roughly evenly. The preference is already on.

## `distribute` — explicit proportions

`distribute` says, for traffic *originating* in a given locality, exactly how it should be spread:

```yaml
trafficPolicy:
  loadBalancer:
    localityLbSetting:
      enabled: true
      distribute:
        - from: local/zone-a/*
          to:
            "local/zone-a/*": 70
            "local/zone-b/*": 30
```

Reading the shape carefully:

- **`from`** is a locality pattern matched against the **caller**.
- **`to`** is a map of destination locality patterns to weights, summing to 100 — the same rule as section 020's route weights.
- `*` is a wildcard over the remaining levels, so `local/zone-a/*` means region `local`, zone `zone-a`, any subzone.

`distribute` **replaces** the default preference for matching callers. Traffic from a locality that matches no `from` entry keeps the default behaviour, so you can target one zone's callers and leave the rest alone.

Use it when strict preference is wrong — for example to keep a warm connection pool open to a second zone, or to deliberately send a slice of traffic across zones so the failover path is exercised before you need it.

> [!TIP]
> **Try it — a deliberate 70/30 cross-zone split**
>
> ```sh
> kubectl apply -f - <<'EOF'
> apiVersion: networking.istio.io/v1
> kind: DestinationRule
> metadata:
>   name: httpbin
>   namespace: locality-demo
> spec:
>   host: httpbin
>   trafficPolicy:
>     loadBalancer:
>       localityLbSetting:
>         enabled: true
>         distribute:
>           - from: local/zone-a/*
>             to:
>               "local/zone-a/*": 70
>               "local/zone-b/*": 30
> EOF
> sleep 3
> kubectl -n locality-demo exec deploy/tester -- sh -c \
>   'for i in $(seq 1 100); do curl -s -o /dev/null http://httpbin:8000/get; done'
> kubectl -n locality-demo logs deploy/tester -c istio-proxy --tail=100 \
>   | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:8080' | sort | uniq -c
> ```
>
> Expect something like:
>
> ```text
>      72 10.244.0.21:8080
>      28 10.244.0.22:8080
> ```
>
> The strict preference from the previous checkpoint is gone, replaced by the proportions you asked for. As with every percentage in this course the draw is per request, so measure over a hundred and expect a few points of wobble.

## `failover` — ordered fallback between regions

`failover` sets no weights. It keeps the default preference and specifies, when a **region** has no healthy endpoints left, which region to use next:

```yaml
trafficPolicy:
  loadBalancer:
    localityLbSetting:
      enabled: true
      failover:
        - from: us-east1
          to: us-west1
```

Two constraints that are commonly tested:

- **`failover` operates at the region level.** It cannot express zone-to-zone fallback inside one region — and it does not need to, because zone spillover within a region is already the default preference behaviour.
- **`distribute` and `failover` are mutually exclusive.** Use one or the other for a given host.

There is also `failoverPriority`, a list of label keys (such as `topology.kubernetes.io/region`) used to rank endpoints by how many labels they share with the caller. It is the more flexible modern alternative and worth recognising, though `failover` is what most task descriptions name.

## Choosing between them

| The requirement says | Use |
| --- | --- |
| "keep traffic in the zone, fall back if it fails" | **nothing** — that is the default |
| "send 30% to the other zone deliberately" | `distribute` |
| "if this region is down, use that one" | `failover` |
| "rank fallbacks by how similar the locality is" | `failoverPriority` |
| "fail over between zones in the same region" | the default already does this |

> *The default already prefers the caller's locality and spills over — `localityLbSetting` exists to change that default, not to create it.*

## Reference

- [Locality load balancing task](https://istio.io/latest/docs/tasks/traffic-management/locality-load-balancing/) — separate pages for distribute, failover and failoverPriority.
- [LocalityLoadBalancerSetting API](https://istio.io/latest/docs/reference/config/networking/destination-rule/#LocalityLoadBalancerSetting) — the schema, including the mutual exclusion.
- [Envoy locality weighted load balancing](https://www.envoyproxy.io/docs/envoy/latest/intro/arch_overview/upstream/load_balancing/locality_weight) — what the weights compile into.
- `istioctl proxy-config endpoints -o json` — the per-endpoint locality the settings above are matching against.
