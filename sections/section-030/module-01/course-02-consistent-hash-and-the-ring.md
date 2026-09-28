# `consistentHash` And The Ring

> Prerequisite: [Endpoint Selection And The `simple` Algorithms](./course-01-endpoint-selection-and-simple-algorithms.md). Next: [Policy Levels And Verification](./course-03-policy-levels-and-verification.md).

Every algorithm in Part 1 spreads traffic. This part is the alternative: instead of choosing by load, the proxy derives the endpoint from a property of the request, so the same input always lands on the same pod. This part covers what you can hash, the mechanism that turns a hash into an endpoint, and the two behaviours that surprise people — sessions moving when the pool changes, and affinity vanishing when the property is absent.

## The four things you can hash

`consistentHash` is the second, mutually exclusive form of `loadBalancer`. Exactly one of these sub-fields is set:

| Field | Hashes | Good for |
| --- | --- | --- |
| `httpHeaderName` | a named request header | a gateway or client that already sets a stable user or tenant id |
| `httpCookie` | a cookie, with `name` and optionally `ttl` | browser traffic, where Istio can *generate* the cookie |
| `useSourceIp: true` | the caller's IP address | the bluntest option; misleading behind NAT or a shared gateway |
| `httpQueryParameterName` | a named query parameter | APIs that carry the identifier in the URL |

`simple` and `consistentHash` cannot both be set. The object is rejected at admission, which is the good kind of failure.

## How a hash becomes an endpoint

The name "consistent hashing" is not decoration — it describes a specific algorithm, and knowing roughly how it works is what lets you predict its behaviour.

Envoy builds a **ring**: a circular space of hash values. Each endpoint is placed at many points around that ring (hundreds, controlled by `minimumRingSize`). To route a request, the proxy hashes the chosen property, finds that position on the ring, and walks clockwise to the first endpoint marker it meets.

```text
        hash("alice")
              │
              ▼
   ┌───────────────────────────┐
   │  ●B    ●A   ●C  ●A   ●B   │   ring positions, many per endpoint
   │        ▲                  │
   │        └── first marker clockwise → endpoint A
   └───────────────────────────┘
```

Two properties fall straight out of that picture, and both are examinable:

- **No state is stored.** The proxy does not remember that `alice` went to pod A. It recomputes the same hash and walks to the same marker every time. That is why affinity survives proxy restarts and needs no shared session store.
- **Removing an endpoint only affects its own arcs.** Take endpoint A out and its markers vanish; requests that used to land on them now walk on to whatever marker is next. Everything that was already landing on B or C is untouched.

That second property is the "consistent" in consistent hashing. A naive `hash(key) % endpoint_count` would remap **almost every** key when the count changes; the ring remaps roughly `1/N` of them.

> [!TIP]
> **Try it — pin one user to one pod**
>
> ```sh
> kubectl -n lb-demo patch destinationrule httpbin --type merge -p '
> spec:
>   trafficPolicy:
>     loadBalancer:
>       consistentHash:
>         httpHeaderName: x-user'
> sleep 2
> kubectl -n lb-demo exec deploy/tester -- sh -c \
>   'for i in $(seq 1 12); do curl -s -o /dev/null http://httpbin:8000/get -H "x-user: alice"; done'
> kubectl -n lb-demo logs deploy/tester -c istio-proxy --tail=12 \
>   | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:8080' | sort | uniq -c
> ```
>
> Expect something like:
>
> ```text
>      12 10.244.0.12:8080
> ```
>
> One endpoint, twelve times. Nothing was stored — the proxy recomputed the same hash of the string `alice` on every request and walked to the same marker. Which pod it is depends on the hash, so yours may differ.

A pin is only meaningful if different values land differently. Repeat the loop with `x-user: bob` and the hash of `bob` selects its own position on the ring — usually a different endpoint, though with only three endpoints two names can legitimately land on the same one. **A collision is not a misconfiguration**; if `alice` and `bob` coincide, try `carol`.

## Affinity is best effort

This is the sentence to be able to say in an exam answer, because "sticky sessions" invites the assumption that stickiness is absolute.

The ring is built from the **current** endpoint set. Add a pod and it inserts new markers, capturing some arcs that previously belonged to its neighbours. Lose a pod and its arcs are absorbed by whoever is next clockwise. Either way, a share of existing sessions moves.

What consistent hashing guarantees is that the share is *small* — roughly one over the number of endpoints, rather than a full reshuffle. Going from three pods to four moves about a quarter of sessions; the other three quarters never notice.

The practical consequence: **treat affinity as an optimisation, not a correctness guarantee.** An application that *breaks* when a session moves is an application that needs shared session state, whatever the load balancer does. Affinity makes the cache hit rate better; it does not make in-memory session state safe.

## A request with nothing to hash

This is the failure mode behind most "affinity works in testing but not in production" reports.

If a request does not carry the hashed property — no `x-user` header, no cookie, no such query parameter — there is nothing to hash. The proxy does not fail the request and does not pick a fixed fallback pod. It **falls back to normal load balancing for that request**.

So a policy hashing a header the client only sometimes sends produces affinity that only sometimes applies, with no error anywhere and no obvious pattern.

> [!TIP]
> **Try it — no header means no affinity**
>
> ```sh
> kubectl -n lb-demo exec deploy/tester -- sh -c \
>   'for i in $(seq 1 12); do curl -s -o /dev/null http://httpbin:8000/get; done'
> kubectl -n lb-demo logs deploy/tester -c istio-proxy --tail=12 \
>   | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:8080' | sort | uniq -c
> ```
>
> Expect something like:
>
> ```text
>       4 10.244.0.11:8080
>       5 10.244.0.12:8080
>       3 10.244.0.13:8080
> ```
>
> The `consistentHash` policy is still applied and unchanged — these requests simply have nothing to hash, so they spread. Compare with the twelve-on-one-pod result from the previous checkpoint: same policy, different requests, completely different behaviour.

## Cookie-based affinity, and the `ttl` switch

Header-based affinity assumes somebody sets the header. For browser traffic a cookie is usually the better fit:

```yaml
trafficPolicy:
  loadBalancer:
    consistentHash:
      httpCookie:
        name: session-id
        ttl: 60s
```

The important detail is what `ttl` does. **Setting `ttl` makes Istio generate the cookie** if the request does not already carry one: the proxy issues a `Set-Cookie` on the response, and the browser returns it on every subsequent request. That closes the "nothing to hash" gap for a client that arrives with no identifier.

Leave `ttl` out and Istio will only hash a cookie the client already sends — which is the right choice when some other component owns the session cookie and a second one would cause confusion.

> *The ring means a hash maps to an endpoint without storing anything, and that changing the endpoint set moves a small share of sessions rather than all of them.*

## Reference

- [ConsistentHashLB API](https://istio.io/latest/docs/reference/config/networking/destination-rule/#LoadBalancerSettings-ConsistentHashLB) — the four hash sources, `minimumRingSize`, and the cookie fields.
- [Envoy ring hash load balancer](https://www.envoyproxy.io/docs/envoy/latest/intro/arch_overview/upstream/load_balancing/load_balancers#ring-hash) — the ring, its size, and the remapping guarantee.
- [Consistent hashing (original paper summary)](https://en.wikipedia.org/wiki/Consistent_hashing) — the `1/N` remapping property in two paragraphs, if you want the reasoning rather than the assertion.
- `istioctl proxy-config cluster <workload> --fqdn <host> -o json` — where `RING_HASH` and `ringHashLbConfig` appear, covered in Part 3.
