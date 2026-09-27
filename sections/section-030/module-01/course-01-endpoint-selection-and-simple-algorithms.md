# Part 1 — Endpoint Selection And The `simple` Algorithms

> Prerequisite: [the module landing page](./course.md). Next: [Part 2 — `consistentHash` And The Ring](./course-02-consistent-hash-and-the-ring.md).

This part establishes where the endpoint decision sits in the request path, gives you a way to watch it happen, and covers the four standard algorithms — all of which have the property that they spread traffic, which is exactly what Part 2 will take away.

## Where the choice happens

Three decisions happen in order inside the calling proxy, and keeping them apart makes the rest of the course easier:

```text
  request
     │
     │  1. ROUTE MATCH            section 010 — which http rule applies
     ▼
  the rule's route block
     │
     │  2. CLUSTER SELECTION      section 020 — weights pick a subset,
     ▼                            or there is only one destination
  one cluster  (outbound|8000|<subset>|httpbin…)
     │
     │  3. ENDPOINT SELECTION     THIS MODULE — pick one pod from the
     ▼                            cluster's endpoint list
  10.244.0.12:8080
```

Step 3 is the only one this module changes. It happens per request, inside the client's sidecar, over the endpoints the control plane pushed for that cluster. Nothing about it involves the server.

That ordering also explains a fact from section 020 that is worth restating: because step 2 finishes before step 3 begins, the number of endpoints in a cluster cannot influence which cluster was chosen.

## Watching a proxy choose

The demo profile writes an Envoy access log to stdout for every proxy, and each line records the **upstream host** — the address of the endpoint the proxy picked. Reading that on the *client* side is the honest way to observe selection, because it is the proxy's own record of its decision rather than something the application chose to report.

> [!TIP]
> **Try it — three endpoints, no policy, no affinity**
>
> ```sh
> kubectl -n lb-demo get endpoints httpbin
> kubectl -n lb-demo exec deploy/tester -- sh -c \
>   'for i in $(seq 1 12); do curl -s -o /dev/null http://httpbin:8000/get -H "x-user: alice"; done'
> kubectl -n lb-demo logs deploy/tester -c istio-proxy --tail=12 \
>   | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:8080' | sort | uniq -c
> ```
>
> Expect something like:
>
> ```text
> NAME      ENDPOINTS                                            AGE
> httpbin   10.244.0.11:8080,10.244.0.12:8080,10.244.0.13:8080   6m
>       4 10.244.0.11:8080
>       4 10.244.0.12:8080
>       4 10.244.0.13:8080
> ```
>
> The IP range depends on your cluster's pod CIDR. Twelve identical requests, all carrying the same `x-user: alice`, spread evenly across all three endpoints — the header means nothing to the proxy, because nothing has told it to care. This is the baseline Part 2 breaks.

## The four `simple` algorithms

`trafficPolicy.loadBalancer` takes one of two mutually exclusive forms. The first is `simple`, which names a standard algorithm:

| Value | Mechanism | Use when |
| --- | --- | --- |
| `LEAST_REQUEST` | tracks outstanding requests per endpoint and sends to the least loaded — the current Istio default | request costs vary; a pod stuck on a slow request should stop receiving new ones |
| `ROUND_ROBIN` | strict rotation through the endpoint list; the default in older Istio versions | request costs are uniform and you want exact even distribution |
| `RANDOM` | uniform random choice, no per-endpoint state | very large endpoint counts, where tracking state costs more than it saves |
| `PASSTHROUGH` | connect to the original destination address, doing no load balancing at all | the client already chose an address and the proxy must not second-guess it |

Two of these deserve a sentence more.

**`LEAST_REQUEST` is not a full scan.** Envoy implements it as "power of two choices": it samples a small number of endpoints at random and sends to whichever of those has the fewest outstanding requests. That gets nearly all the benefit of a full comparison at a fraction of the cost, and it is why the distribution looks slightly uneven rather than perfectly balanced — a genuinely even split would be the signature of round robin.

**`PASSTHROUGH` is the odd one out.** The other three pick from the cluster's endpoint list. `PASSTHROUGH` ignores that list and connects to whatever address the request was originally headed for, which makes it a way to opt *out* of load balancing rather than a way to configure it.

The field sits under `trafficPolicy`, which is where every client-side decision about a destination lives:

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: httpbin
  namespace: lb-demo
spec:
  host: httpbin
  trafficPolicy:
    loadBalancer:
      simple: LEAST_REQUEST
```

> [!TIP]
> **Try it — an explicit algorithm still spreads**
>
> ```sh
> kubectl apply -f - <<'EOF'
> apiVersion: networking.istio.io/v1
> kind: DestinationRule
> metadata:
>   name: httpbin
>   namespace: lb-demo
> spec:
>   host: httpbin
>   trafficPolicy:
>     loadBalancer:
>       simple: LEAST_REQUEST
> EOF
> kubectl -n lb-demo exec deploy/tester -- sh -c \
>   'for i in $(seq 1 12); do curl -s -o /dev/null http://httpbin:8000/get -H "x-user: alice"; done'
> kubectl -n lb-demo logs deploy/tester -c istio-proxy --tail=12 \
>   | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:8080' | sort | uniq -c
> ```
>
> Expect something like:
>
> ```text
>       5 10.244.0.11:8080
>       3 10.244.0.12:8080
>       4 10.244.0.13:8080
> ```
>
> Still all three, now slightly uneven because `LEAST_REQUEST` reacts to in-flight requests rather than counting turns. Switch `simple` to `ROUND_ROBIN` and run it again: with a sequential loop you should see a much flatter 4/4/4. Every `simple` value distributes — that is what they are for.

> *Endpoint selection is the third decision in the path, made per request by the client proxy, and every `simple` algorithm spreads traffic across the cluster's endpoints.*

## Reference

- [LoadBalancerSettings API](https://istio.io/latest/docs/reference/config/networking/destination-rule/#LoadBalancerSettings) — the `simple` enum and the `consistentHash` alternative in one page.
- [Envoy load balancing overview](https://www.envoyproxy.io/docs/envoy/latest/intro/arch_overview/upstream/load_balancing/overview) — what each algorithm does inside the proxy, including power-of-two-choices.
- [Istio access log format](https://istio.io/latest/docs/tasks/observability/logs/access-log/) — the upstream-host field this part relies on.
- `istioctl proxy-config endpoints <workload>` — the endpoint list the algorithm is choosing from.
