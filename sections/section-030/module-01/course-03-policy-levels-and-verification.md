# Part 3 — Policy Levels And Verification

> Prerequisite: [Part 2 — `consistentHash` And The Ring](./course-02-consistent-hash-and-the-ring.md). Next: [the module landing page](./course.md).

A `trafficPolicy` can be attached in three places on one `DestinationRule`, and the rule for which one applies is simple to state and easy to get wrong in a way that silently drops settings. This part covers that, the proxy-side verification, and the module's consolidated pitfalls.

## Three levels, most specific wins

```yaml
spec:
  host: httpbin
  trafficPolicy:                    # 1. HOST level — every subset, every port
    loadBalancer:
      consistentHash:
        httpHeaderName: x-user
  subsets:
    - name: canary
      labels:
        version: canary
      trafficPolicy:                # 2. SUBSET level — this subset only
        loadBalancer:
          simple: ROUND_ROBIN
    - name: stable
      labels:
        version: stable
  # 3. PORT level lives under portLevelSettings, at host or subset scope
```

The precedence is what you would expect — port beats subset beats host — but the combination rule is not:

> A more specific `trafficPolicy` **replaces** the less specific one for the scope it covers. It does not merge field by field.

So in the example above, the `canary` subset gets `ROUND_ROBIN` and **nothing else**. If the host-level policy had also set `connectionPool` or `outlierDetection`, the `canary` subset would not inherit them; its policy is the complete policy for that subset.

This is the single most common way to lose a setting you thought was applied. The symptom is that a host-level circuit breaker or outlier detector "stops working" for exactly one subset — the one that happens to carry its own `trafficPolicy` for an unrelated reason.

The safe habit: when you add a subset-level `trafficPolicy`, restate everything that subset needs, not just the field you are changing.

## Port-level settings

`portLevelSettings` takes a list, each entry naming a port and carrying its own policy:

```yaml
trafficPolicy:
  portLevelSettings:
    - port:
        number: 8000
      loadBalancer:
        simple: LEAST_REQUEST
```

It matters most for a Service exposing several ports with different characteristics — a fast API on one port and a bulk transfer on another. It is also the shape section 070 uses for TLS origination, where `tls` settings must apply to port 443 and emphatically not to port 80.

## Reading the policy from the proxy

Envoy's name for the algorithm is `lbPolicy` on the cluster, and consistent hashing appears as `RING_HASH` with a ring configuration beside it. As always, this separates "my object is wrong" from "my object never arrived".

> [!TIP]
> **Try it — the policy the client proxy is actually using**
>
> ```sh
> istioctl proxy-config cluster deploy/tester -n lb-demo \
>   --fqdn httpbin.lb-demo.svc.cluster.local -o json | grep -E 'lbPolicy|ringHash|minimumRingSize|maglev' -A3
> ```
>
> Expect something like:
>
> ```text
> "lbPolicy": "RING_HASH",
> "ringHashLbConfig": {
>   "minimumRingSize": "1024"
> },
> ```
>
> `RING_HASH` is Envoy's implementation of `consistentHash`, and `minimumRingSize` is how many markers the ring holds — the number that decides how evenly the arcs are distributed. With `simple: LEAST_REQUEST` you would see `LEAST_REQUEST` here and no ring config. If this still shows the previous value, the push has not landed and editing the YAML again will not help.

One useful detail: `lbPolicy` is reported **per cluster**, so a host with subsets has one line per subset. That is the fastest way to confirm a subset-level override actually took effect — you should see two different `lbPolicy` values for the same host.

## Choosing between the two forms

A short decision guide, since exam questions tend to describe a symptom rather than name a field:

| The requirement says | Use |
| --- | --- |
| "distribute evenly", "balance load" | `simple: ROUND_ROBIN` |
| "requests have very different costs", "avoid overloading a busy pod" | `simple: LEAST_REQUEST` |
| "the same user must reach the same instance", "sticky sessions" | `consistentHash` on a header or cookie |
| "session state is held in memory" | `consistentHash` — **and** note that this is best effort, not a guarantee |
| "do not load balance", "connect to the original address" | `simple: PASSTHROUGH` |

## Common pitfalls

> [!WARNING]
> **Expecting perfect stickiness.** Changing the endpoint set moves roughly `1/N` of sessions, by design. Affinity is best effort — say so if asked.
>
> **Hashing a header the client does not always send.** Requests without it fall back to normal load balancing, so the affinity silently applies to only some traffic.
>
> **Setting `simple` and `consistentHash` together.** Mutually exclusive; the object is rejected.
>
> **Testing affinity against one replica.** Every request lands on the same pod whether or not your policy works. Use at least three endpoints.
>
> **Assuming a subset `trafficPolicy` merges with the host-level one.** It replaces it for that subset. Restate everything the subset needs.
>
> **Using `useSourceIp` behind a shared egress address.** Everyone behind the same NAT or gateway hashes identically and lands on one pod.
>
> **Setting `httpCookie` without `ttl` and expecting Istio to create the cookie.** Without `ttl` it only hashes a cookie the client already sends.
>
> **Reading affinity from application behaviour alone.** The client proxy's access log records the chosen upstream, which is the unambiguous evidence.

> *A more specific `trafficPolicy` replaces the less specific one for its scope — it never merges, so a subset policy must restate everything that subset needs.*

## Reference

- [DestinationRule API](https://istio.io/latest/docs/reference/config/networking/destination-rule/) — `trafficPolicy` at host, subset and port level in one schema.
- [TrafficPolicy API](https://istio.io/latest/docs/reference/config/networking/destination-rule/#TrafficPolicy) — every key that can appear at each level, including the ones section 040 adds.
- [Debugging Envoy and istiod](https://istio.io/latest/docs/ops/diagnostic-tools/proxy-cmd/) — the `proxy-config cluster` workflow used above.
- `istioctl proxy-config cluster --help` — `--fqdn`, `--subset` and `--port`, which make the per-cluster `lbPolicy` comparison readable.
