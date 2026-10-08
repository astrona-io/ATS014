# Identifying And Sampling Shadow Traffic

Part 1 ended with a mirror the caller cannot see. That is on purpose, and it leaves a practical question: how do you know the mirror is working? This part answers that. Then it lowers the copy rate, for services where doubling the load is not acceptable.

## Telling a copy apart from real traffic

A mirrored copy is the same request, byte for byte. Older Istio releases made one change to it. They added `-shadow` to the authority (the `Host` header of an HTTP/1 request, or the `:authority` header of an HTTP/2 one). A shadow app could read that header and act differently: skip the database write, skip the email, log instead of act.

```text
  primary request                       mirrored copy (older Istio)
  ───────────────                       ───────────────────────────
  :authority: probe                     :authority: probe-shadow
  GET /hostname                         GET /hostname
  (everything else identical)           (everything else identical)
```

**Istio 1.30, the version this course uses, no longer changes the authority.** A copy arrives with the original `Host`. By its headers alone, it looks exactly like a real request. A lot of older material, and the odd exam question, still describes the suffix. So recognise it, but do not build a check on it.

What still identifies a copy is the routing. In Part 1 the route sent 100% of traffic to v1. So nothing that v2 received can have come from the route. Every request v2 logs is a mirror. That is what you check, and it does not depend on any header.

Two things follow:

- **The receiving side's logs are the evidence**, not the authority string.
- **On 1.30 a shadow cannot tell a copy from the real thing by itself.** If a shadow must not cause side effects, keep it away from the shared database and the outbound mail. Do not rely on it reading a header. Part 3 explains why that matters so much.

## Where the evidence is

There are two logs on the receiving pod, and both work here:

- The **app log**. `count_received` reads it: `probe` writes one line per request it handles.
- The **sidecar access log**. Each sidecar is the communications officer on its ship, and the access log is the ship's black box flight log: one line per request, with the status code and short codes for what went wrong. It is on the receiving pod, so the command names `-c istio-proxy` on the shadow's Deployment, not on the caller.

> [!TIP]
> **Try it – the copies in the shadow sidecar's access log**
>
> With the full mirror to v2 from Part 1 in place:
>
> ```sh
> send_requests 5
> kubectl logs -n starfleet deploy/probe-v2 -c istio-proxy --tail=5
> ```
>
> Expect five lines that each contain something like this (trimmed):
>
> ```text
> "GET /hostname HTTP/1.1" 200 - via_upstream ...
> ```
>
> The v2 pod is serving requests, even though the route sends every request to v1. That is the mirror, and those are requests whose answers the caller never saw. If this log stays empty while the caller is perfectly happy, the mirror is misconfigured. The usual cause is a `mirror.subset` no `DestinationRule` defines.

Read one of those lines carefully once, because the same format appears in every later section:

| Part of the line | Meaning |
| --- | --- |
| `"GET /hostname HTTP/1.1"` | method, path, protocol |
| `200` | the answer the **shadow** gave, which the caller never saw |
| `-` | the response flags; `-` means nothing went wrong |

If the shadow were failing, the second column is where you would see it. A `503` there and a happy caller at the same time is exactly what Part 1's broken-mirror test showed.

## Counting, not reading

For anything beyond a demo, count instead of reading lines. Because the route sends nothing to v2, **every** request v2 receives is a mirrored copy. So counting arrivals counts copies, with no header to match on.

The one thing to get right: logs keep everything from earlier runs. A raw count includes every copy from every earlier test. That is why the helpers work in two steps. `mark_start` notes the time, and `count_received` only counts lines written since then (`kubectl logs --since-time`).

## Sampling with `mirrorPercentage`

A full mirror doubles the traffic inside the cluster. For a busy service, or a shadow you do not yet trust with real load, copy only a share:

```yaml
    mirrorPercentage:
      value: 20.0
```

The value is a decimal number. It is the share of **matched** requests that get copied. If you leave the block out, every matched request is mirrored. **The default is 100%, not 0%.** That is an easy thing to get wrong in the exam.

As with weighted routing, the sidecar decides for each request on its own. So the same sampling advice applies: measure over many requests, not a handful.

> [!TIP]
> **Try it – mirror only 20%**
>
> Change `value: 100.0` to `value: 20.0` under `mirrorPercentage` in `virtualservice-probe.yaml`, then apply and count 30 requests:
>
> ```sh
> kubectl apply -f virtualservice-probe.yaml
> mark_start; send_requests 30; count_received
> ```
>
> Expect something like:
>
> ```text
>   30 probe-v1
> probe-v1 received: 30
> probe-v2 received: 5
> ```
>
> About 6 is expected; the number is random and differs a little each run. Lower the share whenever v2 cannot handle the full load of real users.

## Sampling is not filtering

Two ideas are easy to mix up, and a task may ask for either.

`mirrorPercentage` picks a **random share of requests**. It gives the shadow a fair sample of real traffic, which is what you want for load and crash testing.

A `match` block picks a **specific kind of request**. A mirror on a rule that matches `x-internal: true` copies only internal traffic. That is predictable and repeatable, and it is not a fair sample of anything.

You can combine them. A rule that matches internal traffic with `mirrorPercentage: 100`, plus a catch-all rule with `mirrorPercentage: 10`, gives you every internal request and a tenth of everything else. Each `http` rule has its own mirror settings. There is no mesh-wide mirror.

## Common pitfalls

> [!WARNING]
> **Looking for a `-shadow` authority suffix.** Istio 1.30 does not add one. Older docs and some exam material still describe it. The routing, not a header, is what identifies a copy.
>
> **Counting a log without a start point.** Logs keep earlier runs. Use `mark_start` (or a before-and-after count), or you measure every test you have ever done.
>
> **Assuming a missing `mirrorPercentage` means no mirroring.** The default is 100%.
>
> **Looking for the evidence on the caller.** The caller sees nothing. The receiving pod's logs are the only place a copy shows up.

> *A copy is invisible to the caller and, on Istio 1.30, looks the same as a real request. The receiving pod's logs are where a mirror proves it is working.*
