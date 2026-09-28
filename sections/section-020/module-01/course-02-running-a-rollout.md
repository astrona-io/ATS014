# Running A Rollout

> Prerequisite: [Weighted Destinations](./course-01-weighted-destinations.md). Next: [Weight Versus Replicas, And Proof](./course-03-weight-versus-replicas-and-proof.md).

A canary release has no special machinery in Istio. It is the object from Part 1, applied a few times with different numbers. This part is about doing that safely: how the edit works, how fast it takes effect, and how to measure the result without drawing a conclusion the sample cannot support.

## Measuring a statistical split

Part 1 established that each request is an independent draw. The practical consequence is that a small sample tells you almost nothing.

At a true 80/20 split, ten requests coming out 10/0 is unremarkable — it happens roughly one time in ten. Concluding from that that the weights are broken, and "fixing" a configuration that was correct, is the most common self-inflicted confusion on this topic.

A rough guide for reading your own tests:

| Sample size | What you can conclude at a nominal 80/20 |
| --- | --- |
| 10 | almost nothing; 10/0 and 6/4 are both ordinary |
| 100 | the split is in the right region — expect roughly 75–85 |
| 1000 | the number is close to the weight, within a percent or two |

Use 100 as the working minimum, and expect a few percent of wobble even then. If a task says "confirm the split", it means over enough requests to be meaningful.

## Changing the weights

A merge patch is the shortest way to change the numbers, and it is what a rollout script does:

```sh
kubectl -n shifting-demo patch virtualservice notification --type merge -p '
spec:
  http:
    - route:
        - destination:
            host: notification-service
            subset: v1
          weight: 80
        - destination:
            host: notification-service
            subset: v2
          weight: 20'
```

Note that the patch restates the **entire** `http` list, including the parts that did not change. That is not verbosity — it is required. A JSON merge patch **replaces** an array wholesale rather than merging it element by element, because there is no key by which elements could be matched up. The same trap applies to `egress[].hosts` in section 010's `Sidecar` and to every other list in every Istio object.

The practical rule: **for any list-valued field, restate the whole list, or use `kubectl apply` with the complete object.** Reaching for `--type json` and an index-based path works but is brittle; indexes shift.

> [!TIP]
> **Try it — shift 20% and count 100 requests**
>
> ```sh
> kubectl -n shifting-demo patch virtualservice notification --type merge -p '
> spec:
>   http:
>     - route:
>         - destination:
>             host: notification-service
>             subset: v1
>           weight: 80
>         - destination:
>             host: notification-service
>             subset: v2
>           weight: 20'
> kubectl -n shifting-demo exec deploy/tester -- sh -c \
>   'for i in $(seq 1 100); do curl -s -X POST http://notification-service/notify; echo; done' | sort | uniq -c
> ```
>
> Expect something like:
>
> ```text
>   83 ["EMAIL"]
>   17 ["EMAIL","SMS"]
> ```
>
> Your numbers will differ by a few either way — 17 and 23 are both a correct 20% split of 100 samples. Run the same loop again and you will get a different pair. That variation is the mechanism, not a fault.

## How fast a change lands

The patch takes effect in about as long as an xDS push takes: a second or two on a small cluster. No pod restarts, no connections drain, no Deployment is touched. The application is not aware that anything happened.

That property is what makes weighted routing worth the configuration. The interesting number is not how fast you can shift traffic *to* a new version — it is how fast you can shift it *away*:

```text
  100/0  ──►  90/10  ──►  50/50  ──►  0/100        a rollout
                   ▲
                   └──────────────────────────      a rollback: one apply, seconds
```

Rollback is not a special operation and needs no separate procedure. It is the previous numbers, applied again. Compare with a Deployment rollback, which recreates pods and takes as long as your readiness probes allow.

> [!TIP]
> **Try it — finish the rollout, then reverse it**
>
> ```sh
> kubectl -n shifting-demo patch virtualservice notification --type merge -p '
> spec:
>   http:
>     - route:
>         - destination:
>             host: notification-service
>             subset: v2
>           weight: 100'
> kubectl -n shifting-demo exec deploy/tester -- sh -c \
>   'for i in $(seq 1 40); do curl -s -X POST http://notification-service/notify; echo; done' | sort | uniq -c
> ```
>
> Expect something like:
>
> ```text
>   40 ["EMAIL","SMS"]
> ```
>
> The rollout is complete. Now re-run the same patch with `subset: v1` and count again — forty `["EMAIL"]`, within seconds. Nothing about either Deployment changed at any point in this sequence, which is why the reversal is as cheap as the advance.

## A rule above the weights changes the population

One interaction is worth thinking through, because it is easy to leave in place by accident and it quietly invalidates your measurement.

Rules are still evaluated top down, first match wins. A header match sitting **above** your weighted rule removes those requests from the split entirely:

```yaml
http:
  - match:                          # internal testers: always v2
      - headers:
          x-internal:
            exact: "true"
    route:
      - destination: { host: notification-service, subset: v2 }
  - route:                          # everyone else: the canary split
      - destination: { host: notification-service, subset: v1 }
        weight: 90
      - destination: { host: notification-service, subset: v2 }
        weight: 10
```

This is a genuinely useful pattern — pin your own team to the new version while the public sees 10% of it. It is also a trap if you forget the first rule exists and then wonder why your measured split does not match the weights: the requests carrying that header were never part of the population the weights apply to.

The weights still sum to 100 **within their own route block**. Each `http` rule is quantified independently; there is no global budget across rules.

> *A weight change is one apply and takes effect in seconds — which makes the rollback, not the rollout, the reason to use it.*

## Reference

- [Traffic shifting task](https://istio.io/latest/docs/tasks/traffic-management/traffic-shifting/) — the canonical step-by-step rollout.
- [Canary deployments with Istio](https://istio.io/latest/blog/2017/0.1-canary/) — why traffic share and instance count are separated, from the people who separated them.
- [JSON Merge Patch (RFC 7386)](https://datatracker.ietf.org/doc/html/rfc7386) — the two-paragraph reason a merge patch replaces an array.
- `kubectl patch --help` — the difference between `merge`, `strategic` and `json` patch types, which matters for every list field in this course.
