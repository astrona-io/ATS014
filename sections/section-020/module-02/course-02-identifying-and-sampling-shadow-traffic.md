# Identifying And Sampling Shadow Traffic

Astronaut, a mirror is invisible to the sender. That is on purpose, and it leaves a practical question: how do you know the mirror is working at all? This part shows where the proof is. Then it lowers the copy rate, for services where doubling the load is not acceptable.

The commands below need the `probe` `DestinationRule` with the subsets `v1` and `v2`, the flight plan that sends every signal to v1 and mirrors 100% to v2, and the `mark_start`, `count_received` and `send_requests` helpers pasted into your terminal.

## Telling a copy apart from real traffic

A copy is the same signal, byte for byte. Older Istio releases made one change to it: they added `-shadow` to the host name the signal was addressed to, so `probe` became `probe-shadow`. A shadow app could read that and act differently, for example skip a database write.

**Istio 1.30, the version this course uses, no longer does that.** A copy arrives with the original host name. By its headers alone, it looks exactly like a real signal. Older material, and the odd exam question, still describes the suffix, so recognise it, but never build a check on it.

What still identifies a copy is the routing. The flight plan sends 100% of the signals to v1, so nothing v2 receives can have come from the route. **Every signal v2 receives is a copy.** That is what you check, and it does not depend on any header.

## Where the proof is

There are two logs on the receiving ship, and both work:

- The **app log**. `count_received` reads it: the probe writes one line per signal it handles.
- The **flight log** of its communications officer (the access log). It is on the receiving pod, so the command names `-c istio-proxy` on the shadow's Deployment, not on the shuttle.

<!-- astrona:playground:renew -->

### Find the copies in the shadow's flight log

Send a few signals, then read the last two lines of v2's flight log, and the last line of the shuttle's:

```sh
send_requests 5
kubectl logs -n starfleet deploy/probe-v2 -c istio-proxy --tail=2
kubectl logs -n starfleet deploy/shuttle -c istio-proxy --tail=1
```

You should see (the first line is the shuttle's `send_requests` answer):

```text
   5 probe-v1
[2026-10-08T20:32:54.635Z] "GET /hostname HTTP/1.1" 200 - via_upstream - "-" 0 45 0 0 "10.244.0.6" "curl/8.11.1" "2baad0f9-88f4-4cc3-90be-f78b92ea72d8" "probe:8000" "10.244.0.8:8080" inbound|8080|| 127.0.0.6:45293 10.244.0.8:8080 10.244.0.6:0 outbound_.8000_.v2_.probe.starfleet.svc.cluster.local default
[2026-10-08T20:32:54.695Z] "GET /hostname HTTP/1.1" 200 - via_upstream - "-" 0 45 0 0 "10.244.0.6" "curl/8.11.1" "a19acd54-cfbb-4d6a-a3f5-80ba54c8b36a" "probe:8000" "10.244.0.8:8080" inbound|8080|| 127.0.0.6:45293 10.244.0.8:8080 10.244.0.6:0 outbound_.8000_.v2_.probe.starfleet.svc.cluster.local default
[2026-10-08T20:32:54.695Z] "GET /hostname HTTP/1.1" 200 - via_upstream - "-" 0 46 1 0 "-" "curl/8.11.1" "a19acd54-cfbb-4d6a-a3f5-80ba54c8b36a" "probe:8000" "10.244.0.7:8080" outbound|8000|v1|probe.starfleet.svc.cluster.local 10.244.0.6:55596 10.96.35.237:8000 10.244.0.6:32936 - -
```

Your times, IDs and addresses will be different. Three things in these lines prove the mirror works:

```text
outbound_.8000_.v2_.probe...   on v2's line: the signal came in through the v2 subset, which the route never uses
"probe:8000"                    the host name is unchanged: no -shadow suffix on Istio 1.30
"a19acd54-..."                  the same request ID on v2's line and on the shuttle's line
```

The last one is the clearest. The shuttle's line shows request `a19acd54-…` went to `outbound|8000|v1|…`. v2's line shows the **same request ID** arriving at v2. One signal from the shuttle, received by two ships: the original went to v1, the copy to v2.

If v2's flight log stays empty while the shuttle is perfectly happy, the mirror is not sending.

## Counting, not reading

For anything beyond a quick look, count instead of reading lines. Because the route sends nothing to v2, every signal v2 receives is a copy, so counting arrivals counts copies.

The one thing to get right: logs keep everything from earlier runs. A raw count includes every copy from every earlier test. That is why the helpers work in two steps: `mark_start` notes the time, and `count_received` only counts log lines written since then.

## Sampling with `mirrorPercentage`

A full mirror doubles the signals inside the solar system. For a busy service, or a shadow you do not yet trust with real load, copy only a share. The value under `mirrorPercentage` is the share of **matched** signals that get a copy, as a decimal number.

If you leave `mirrorPercentage` out, every matched signal is copied. **The default is 100%, not 0%.** That is easy to get wrong in the exam.

The proxy decides for each signal on its own, like a coin flip with your odds. So count many signals before you judge the share.

### Copy only 20%

Save this as `virtualservice-probe.yaml`, replacing the old file:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: probe
  namespace: starfleet
spec:
  hosts:
  - probe
  http:
  - route:
    - destination:
        host: probe
        subset: v1
    mirror:
      host: probe
      subset: v2
    mirrorPercentage:
      value: 20.0
```

Apply it:

```sh
kubectl apply -f virtualservice-probe.yaml
```

Then send 30 signals, and after that 100:

```sh
mark_start; send_requests 30; count_received
mark_start; send_requests 100; count_received
```

You should see something like:

```text
  30 probe-v1
probe-v1 received: 30
probe-v2 received: 4
 100 probe-v1
probe-v1 received: 100
probe-v2 received: 20
```

At 30 signals, 4 copies is a little under 20%: a small sample wanders. At 100 signals it lands on 20. Your numbers will differ a little on every run.

## Sampling is not filtering

Two ideas are easy to mix up, and a task may ask for either.

- `mirrorPercentage` picks a **random share** of signals. It gives the shadow a fair sample of real traffic, which is what you want for load and crash testing.
- A `match` block picks a **specific kind** of signal. A mirror on a rule that matches the header `x-internal: true` copies only internal traffic. That is predictable, but it is not a fair sample of anything.

You can combine them. A rule that matches internal signals with `mirrorPercentage` at 100, followed by a catch-all rule with `mirrorPercentage` at 10, copies every internal signal and a tenth of everything else. Each `http` rule has its own mirror settings. There is no mirror for the whole mesh.

## Common pitfalls

> [!WARNING]
> - **Looking for a `-shadow` host name suffix.** Istio 1.30 does not add one. The routing, not a header, is what identifies a copy.
> - **Counting a log without a start point.** Logs keep earlier runs. Use `mark_start`, or you measure every test you have ever done.
> - **Assuming a missing `mirrorPercentage` means no mirroring.** The default is 100%.
> - **Looking for the proof on the sender.** The sender sees nothing. The receiving ship's logs are the only place a copy shows up.
> - **Judging a percentage from a handful of signals.** Count at least 100.

> *A copy is invisible to the sender and, on Istio 1.30, looks the same as a real signal. The receiving ship's flight log is where a mirror proves it works.*

## Your mission: Mirror Live Traffic To A Shadow Service

You can now add a mirror, prove from the receiving side that copies arrive, and control the copied share. Now prove it in a graded mission: send all traffic to the stable version and copy every signal to the release candidate, without a single user seeing its answer.

The mission runs in its own training solar system, so first pause your playground. Nothing in it is lost:

```sh
astrona stop ats-014-playground-020-02
```

Then start the mission:

```sh
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-020/module-02/labs/lab-01
```

Read the task in [`question.md`](./labs/lab-01/question.md) and solve it on your own first. When you think you are done, send it for grading:

```sh
astrona submit -c sections/section-020/module-02/labs/lab-01
```

When the mission is done, remove it and wake your playground up again:

```sh
astrona destroy ats-014-lab-020-02
astrona start ats-014-playground-020-02
```
