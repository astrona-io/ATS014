# Part 2 — Identifying And Sampling Shadow Traffic

> Prerequisite: [Part 1 — Mirror As A Sibling Of Route](./course-01-mirror-as-a-sibling-of-route.md). Next: [Part 3 — Consequences, Verification And Limits](./course-03-consequences-verification-and-limits.md).

Part 1 ended with a mirror that is completely invisible from the caller. That is by design, and it leaves a practical problem: how do you know it is working? This part answers that, and then reduces the copy rate for services where doubling the load is not acceptable.

## The `-shadow` suffix

When Istio dispatches a mirrored copy it **rewrites the authority**. The `Host` header of an HTTP/1 request, or the `:authority` pseudo-header of an HTTP/2 one, has `-shadow` appended:

```text
  primary request                       mirrored copy
  ───────────────                       ─────────────
  :authority: notification-service      :authority: notification-service-shadow
  POST /notify                          POST /notify
  (everything else identical)           (everything else identical)
```

The suffix exists for the receiving application's benefit, not yours. A shadow deployment can read the authority and decide to behave differently — skip the database write, skip the outbound email, log instead of act. That is the sanctioned way to make a shadow safe, and Part 3 explains why it matters so much.

Two consequences for you right now:

- **It is the signature that identifies a mirrored request** at the destination, which makes it the thing to grep for.
- **It only helps if the application looks at it.** Istio rewrites the header; it does not enforce anything. A shadow that ignores the authority does the full work of every copy.

## Where the evidence is

Application logs may or may not record the authority. The **proxy** access log always does, and it is on the receiving pod — so the command names `-c istio-proxy` on the shadow's Deployment rather than on the caller.

> [!TIP]
> **Try it — the `-shadow` authority in the shadow proxy's access log**
>
> ```sh
> kubectl -n mirror-demo logs -l version=v2 -c istio-proxy --tail=20 | grep -i shadow
> ```
>
> Expect something like:
>
> ```text
> [2026-09-27T10:14:02.771Z] "POST /notify HTTP/1.1" 200 - via_upstream - "-" 0 16 1 1 "-" "curl/8.5.0" "9b1a..." "notification-service-shadow" "10.244.0.9:8084" ...
> ```
>
> The quoted `notification-service-shadow` is the rewritten authority. These twenty log lines are the twenty requests the caller never saw a response from. An empty result here while the caller is perfectly happy is the signature of a misconfigured mirror — most often a `mirror.subset` no `DestinationRule` defines.

Reading one of those lines is worth doing carefully once, because the same format appears in every remaining section of this course. The fields that matter here:

| Field in the line | Meaning |
| --- | --- |
| `"POST /notify HTTP/1.1"` | method, path, protocol |
| `200` | the response the **shadow** produced — which the caller never saw |
| `"notification-service-shadow"` | the rewritten authority: this is a mirrored request |
| `"10.244.0.9:8084"` | the upstream host that served it |

Note the `200` in that line. If the shadow were failing, this is where you would see it — a `500` here and a happy caller at the same time is exactly the situation mirroring exists to create.

## Counting instead of eyeballing

For anything beyond a demonstration, count rather than read. Comparing the shadow's request count against the number you sent is the cleanest confirmation that a mirror is running at the rate you configured.

## Sampling with `mirrorPercentage`

Full mirroring doubles the cluster's internal request volume. For a heavy service, or a shadow not yet trusted with real load, copy a fraction instead:

```yaml
mirrorPercentage:
  value: 50.0
```

The value is a float and it is the share of **matched** requests that get copied. Omit the block entirely and everything matched is mirrored — the default is 100%, not 0%, which is a reasonable thing to get wrong in an exam.

As with weighted routing, the decision is made per request and independently, so the same sampling caution applies: measure over a hundred requests, not ten.

> [!TIP]
> **Try it — halve the mirror and count both sides**
>
> ```sh
> kubectl -n mirror-demo patch virtualservice notification --type merge -p '
> spec:
>   http:
>     - route:
>         - destination:
>             host: notification-service
>             subset: v1
>           weight: 100
>       mirror:
>         host: notification-service
>         subset: v2
>       mirrorPercentage:
>         value: 50.0'
> BEFORE=$(kubectl -n mirror-demo logs -l version=v2 -c istio-proxy --tail=-1 2>/dev/null | grep -c shadow)
> kubectl -n mirror-demo exec deploy/tester -- sh -c \
>   'for i in $(seq 1 100); do curl -s -o /dev/null -X POST http://notification-service/notify; done'
> sleep 2
> AFTER=$(kubectl -n mirror-demo logs -l version=v2 -c istio-proxy --tail=-1 2>/dev/null | grep -c shadow)
> echo "mirrored this run: $((AFTER - BEFORE)) of 100"
> ```
>
> Expect something like:
>
> ```text
> mirrored this run: 54 of 100
> ```
>
> Roughly half — your number will differ by a few. Taking a `BEFORE` count and subtracting is the reason this is trustworthy: the log still holds the copies from the earlier 100% run, so a raw `grep -c` would count those too and report a rate far above 50%.

## Sampling is not filtering

One distinction worth drawing, because the two are easy to conflate and a task may ask for either.

`mirrorPercentage` picks a **random subset of requests**. It gives the shadow a statistically representative slice of production, which is what you want for load and crash testing.

A `match` block picks a **specific kind of request**. Putting a mirror on a rule that matches `x-internal: true` copies only internal traffic — deterministic, repeatable, and not representative of anything.

They compose. A rule matching internal traffic with `mirrorPercentage: 100`, plus a catch-all rule with `mirrorPercentage: 10`, gives you every internal request and a tenth of everything else. Each `http` rule carries its own mirror settings; there is no global mirror.

> *Istio appends `-shadow` to the authority of every copy — the receiving proxy's access log is where a mirror proves it is working.*

## Reference

- [Mirroring task](https://istio.io/latest/docs/tasks/traffic-management/mirroring/) — including the authority rewrite and percentage examples.
- [Envoy access log format](https://www.envoyproxy.io/docs/envoy/latest/configuration/observability/access_log/usage) — what each field in those log lines is, once, so the rest of the course reads faster.
- [Default access log format in Istio](https://istio.io/latest/docs/tasks/observability/logs/access-log/) — how to turn it on if a cluster does not have it, and what the fields mean in Istio's ordering.
- `kubectl logs --tail=-1` — the flag that reads the whole buffer rather than the last few lines, which matters when you are counting.
