# Weight Versus Replicas, And Proof

> Prerequisite: [Running A Rollout](./course-02-running-a-rollout.md). Next: [the module landing page](./course.md).

One idea remains, and it is the single most reliably examined thing in this module: the relationship between how much traffic a version receives and how many pods it runs. This part settles that, then shows how to read the weights out of a live proxy so that a task which is not working can be diagnosed rather than guessed at.

## The two decisions are made in sequence

Part 1's diagram had the answer in it. Expand the bottom half:

```text
  client proxy (in the CALLING pod)
        │
        │  1. WEIGHTED CLUSTER SELECTION
        │     draw against the weights  →  picks a SUBSET
        │     80 / 20
        ├────────────────┐
        │                │
        ▼                ▼
   cluster …|v1|…   cluster …|v2|…
   10 endpoints      1 endpoint
        │                │
        │  2. ENDPOINT LOAD BALANCING
        │     spread within the chosen cluster  →  picks a POD
        ▼                ▼
   ~8% each         100% of v2's share
```

The weight decides **which cluster**. Load balancing then decides **which endpoint inside it**. The second decision has no way to influence the first, because the first already happened.

So the general rule: **weights control traffic share, replicas control capacity.** They live in different objects, are changed for different reasons, and do not interact.

Concretely, with `v1` on ten pods and `v2` on one, at 50/50:

- half of all requests go to the `v2` cluster, and its single pod receives all of them;
- the other half is spread across ten `v1` pods, so each receives about 5% of total traffic.

Scaling `v2` to ten pods does not change its 50% share. It changes how much capacity is available to absorb that share — which is a real and important thing to get right, just not a traffic-splitting control.

> [!TIP]
> **Try it — four times the pods, same share**
>
> ```sh
> kubectl -n shifting-demo patch virtualservice notification --type merge -p '
> spec:
>   http:
>     - route:
>         - destination:
>             host: notification-service
>             subset: v1
>           weight: 50
>         - destination:
>             host: notification-service
>             subset: v2
>           weight: 50'
> kubectl -n shifting-demo scale deployment notification-service-v1 --replicas=4
> kubectl -n shifting-demo rollout status deployment notification-service-v1
> kubectl -n shifting-demo exec deploy/tester -- sh -c \
>   'for i in $(seq 1 100); do curl -s -X POST http://notification-service/notify; echo; done' | sort | uniq -c
> ```
>
> Expect something like:
>
> ```text
>   51 ["EMAIL"]
>   49 ["EMAIL","SMS"]
> ```
>
> Four `v1` pods against one `v2` pod, and the split is still 50/50. If replica count influenced traffic share you would be looking at roughly 80/20. Scale `v1` back to 1 afterwards if you want a tidy environment.

## Where the endpoints went

The endpoint listing makes the same point structurally rather than statistically, and it is the faster check when you are diagnosing rather than demonstrating.

> [!TIP]
> **Try it — one cluster with four endpoints, one with a single endpoint**
>
> ```sh
> for s in v1 v2; do
>   echo "--- subset $s ---"
>   istioctl proxy-config endpoints deploy/tester -n shifting-demo \
>     --cluster "outbound|80|$s|notification-service.shifting-demo.svc.cluster.local"
> done
> ```
>
> Expect something like:
>
> ```text
> --- subset v1 ---
> ENDPOINT            STATUS    OUTLIER CHECK   CLUSTER
> 10.244.0.14:8084    HEALTHY   OK              outbound|80|v1|notification-service...
> 10.244.0.18:8084    HEALTHY   OK              outbound|80|v1|notification-service...
> 10.244.0.19:8084    HEALTHY   OK              outbound|80|v1|notification-service...
> 10.244.0.20:8084    HEALTHY   OK              outbound|80|v1|notification-service...
> --- subset v2 ---
> ENDPOINT            STATUS    OUTLIER CHECK   CLUSTER
> 10.244.0.15:8084    HEALTHY   OK              outbound|80|v2|notification-service...
> ```
>
> Four endpoints and one endpoint, in two clusters that the weights treat as equals. The asymmetry is entirely below the weighted decision — which is exactly why the weight does not see it.

## Reading the weights the proxy holds

The object existing in `kubectl` and the proxy acting on it are separate facts, as always. Weighted routes appear in the proxy's route dump as a `weightedClusters` block with one entry per destination.

> [!TIP]
> **Try it — the weights inside the client's route table**
>
> ```sh
> istioctl proxy-config routes deploy/tester -n shifting-demo -o json \
>   | grep -A12 weightedClusters | head -24
> ```
>
> Expect something like:
>
> ```text
> "weightedClusters": {
>   "clusters": [
>     {
>       "name": "outbound|80|v1|notification-service.shifting-demo.svc.cluster.local",
>       "weight": 50
>     },
>     {
>       "name": "outbound|80|v2|notification-service.shifting-demo.svc.cluster.local",
>       "weight": 50
>     }
> ```
>
> The subset name is embedded in the cluster name — `|v1|` and `|v2|` — which is how a weighted route and a `DestinationRule` subset are joined together inside Envoy. If these weights disagree with your `VirtualService`, the push has not landed and editing the YAML again will not help.

That last sentence is the diagnostic rule for this module. Three possible states, three different actions:

| What you see | Means | Do |
| --- | --- | --- |
| No `weightedClusters` at all | the `VirtualService` never reached this proxy | check namespace, host name, and `istioctl proxy-status` |
| Weights present but stale | the push is in flight or the proxy is out of sync | wait, then check `proxy-status` |
| Weights correct, traffic wrong | your sample is too small, or a rule above is diverting traffic | count 100+, and re-read the whole `http` list |

## Common pitfalls

> [!WARNING]
> **Weights that do not sum to 100.** Rejected at admission with a message naming the total. Read it instead of re-applying.
>
> **Judging a split from ten requests.** Each request is an independent draw. Use 100 or more before concluding anything.
>
> **Scaling a Deployment to move traffic.** Replica count is capacity, not share. Only the weight moves traffic.
>
> **A match rule above the weighted rule.** Those requests never enter the split, so your measurement is of a different population than you think.
>
> **Assuming a merge patch edits one element of `http`.** It replaces the list. Restate the whole route block, or use `kubectl apply`.
>
> **Expecting per-user stickiness from weights.** Each request is drawn independently, so the same client can bounce between versions. For stickiness use a header match (section 010) or `consistentHash` (section 030).
>
> **Weighting a subset that does not exist.** The 100-sum check passes; the requests 503. `istioctl analyze` catches it.

> *Weights control traffic share and replicas control capacity — they are set in different objects, for different reasons, and neither one moves the other.*

## Reference

- [Traffic shifting task](https://istio.io/latest/docs/tasks/traffic-management/traffic-shifting/) — including the scaling discussion.
- [DestinationRule API](https://istio.io/latest/docs/reference/config/networking/destination-rule/) — the object whose subsets the weights point at.
- [Debugging Envoy and istiod](https://istio.io/latest/docs/ops/diagnostic-tools/proxy-cmd/) — `proxy-status` and `proxy-config`, the two commands in the diagnostic table above.
- `istioctl proxy-config routes --help` — `-o json` and `--name`, which make the weighted-cluster block findable on a busy proxy.
