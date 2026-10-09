# Overflow And Its Signatures

Astronaut, a `503` on its own tells you very little. The app could have sent it. A pod could be unready. A route could lead nowhere. This part shows the two pieces of evidence that point to the shields and nothing else. They are the difference between finding an overload and chasing a bug in a ship that works perfectly.

The commands below need the two helpers from the module's landing page and the `probe` `DestinationRule` with all three limits set to `1`, saved as `destinationrule-probe-connection-pool.yaml`.

## The `UO` response flag

Every communications officer keeps a flight log: one line per signal, with a short code called a **response flag** that says how the signal ended. This is the one that matters here:

> **`UO`, upstream overflow.** The shields refused the signal.

An app's own `503` has no such flag. So the first question for any unexplained `503` is not "what is wrong with the probe?". It is "does the *sender's* flight log say `UO`?".

<!-- astrona:playground:renew -->

### Find the flag in the sender's flight log

Fire 30 signals, 4 at a time, and keep only the lines that say `UO`:

```sh
load_test 4 >/dev/null
kubectl logs -n starfleet deploy/fortio -c istio-proxy --tail=40 | grep ' UO ' | head -2
```

You should see lines like these (trimmed):

```text
"GET /get HTTP/1.1" 503 UO upstream_reset_before_response_started{overflow} ... "probe:8000" "-" outbound|8000||probe.starfleet.svc.cluster.local ...
"GET /get HTTP/1.1" 503 UO upstream_reset_before_response_started{overflow} ... "probe:8000" "-" outbound|8000||probe.starfleet.svc.cluster.local ...
```

`503`, `UO` and `overflow` sit on the same line. Two details matter. This is the **sender's** flight log, from `fortio`. And the chosen ship address is `"-"`: the signal never left the sender.

### Count the refusals on both sides

Now compare the sender's refusals with the `503`s the probe pods logged themselves:

```sh
SENDER_UO=$(kubectl logs -n starfleet deploy/fortio -c istio-proxy --tail=100 | grep -c ' 503 UO ')
PROBE_503=$(kubectl logs -n starfleet -l app=probe -c istio-proxy --tail=100 | grep -c ' 503 ')
echo "sender-side UO refusals: $SENDER_UO"
echo "probe-side 503s:         $PROBE_503"
```

You should see something like:

```text
sender-side UO refusals: 20
probe-side 503s:         1
```

Nearly every refusal happened on the sender's side, and the probe never heard of those signals. The few `503`s in the probe's own log are not app errors either. Look at one:

```sh
kubectl logs -n starfleet -l app=probe -c istio-proxy --tail=100 | grep ' 503 '
```

```text
"GET /get HTTP/1.1" 503 UO upstream_reset_before_response_started{overflow} ... "probe:8000" "-" inbound|8080|| ...
```

It is also `UO`, but on the `inbound` side: the probe pod's own communications officer turned the signal away at its door. The same limits apply on both ends. Either way, the probe's app never saw a refused signal. That gap is also why a report that "the probe is returning `503`s" can be wrong about *which* ship is involved.

## The overflow counters

Flight logs roll over. Counters keep adding up. For anything after the fact, the counters are better evidence, and they also tell you *which* limit was hit.

You read them with `pilot-agent request`, a small tool inside every Istio proxy container that talks to the proxy's local administration page. `request GET stats` asks the proxy for its counters.

Each counter starts with the cluster name, here `cluster.outbound|8000||probe.starfleet.svc.cluster.local`:

| Counter | Goes up when |
| --- | --- |
| `upstream_rq_pending_overflow` | a signal was refused because the **waiting queue** was full |
| `upstream_cx_overflow` | the **connection** limit was reached |
| `upstream_rq_pending_active` | signals waiting right now (a live value, not a running total) |

`upstream_rq_pending_overflow` is the counter to name when someone asks how to prove the shields went up.

A standard Istio sidecar does not keep these counters. It keeps only a small set by default, and per-cluster counters like these are not in it, so the `grep` comes back empty. That looks exactly like "the shields never went up". You add them for one ship with an annotation on the **sender's** pod template:

```yaml
template:
  metadata:
    annotations:
      sidecar.istio.io/statsInclusionPrefixes: "cluster.outbound"
```

The playground's `fortio` already has it. Changing it restarts the pod, and the counters start again from zero.

### Read the overflow counters

Fire another 30 signals, 3 at a time, then read the counters:

```sh
load_test 3 >/dev/null
overflow_stats
```

You should see three lines in this shape (your numbers will be different):

```text
cluster.outbound|8000||probe.starfleet.svc.cluster.local;.upstream_cx_overflow: 157
cluster.outbound|8000||probe.starfleet.svc.cluster.local;.upstream_rq_pending_active: 0
cluster.outbound|8000||probe.starfleet.svc.cluster.local;.upstream_rq_pending_overflow: 109
```

`upstream_rq_pending_overflow` counts signals refused because no waiting slot was free. `upstream_cx_overflow` counts the times the connection limit itself was the problem. `upstream_rq_pending_active` is `0` because nothing is in flight while you read it. All of these add up from the moment the proxy started, so note the values before a run if you want the number for one run.

## Reading the numbers together

The two overflow counters answer different questions. Together they tell you which limit to change:

- **`upstream_rq_pending_overflow` high:** signals arrive faster than the open connections can clear them. Raising `http1MaxPendingRequests` buys more waiting room. Raising `maxConnections` buys more throughput.
- **`upstream_cx_overflow` high:** the connection limit is the bottleneck. Raise `maxConnections`.
- **Both unchanged while you see `503`s:** it is not the shields. Look at the app, the route, or the list of pods behind the Service.

> [!TIP]
> When you see an unexplained `503`, read the flag in the **sender's** flight log first. `UO` means the shields. No flag means the answer is somewhere else.

## Common pitfalls

> [!WARNING]
> - **Looking for a refused signal in the probe's app.** The app never saw it. The evidence is in the flight logs and counters of the proxies.
> - **Reading a bare `503` as the shields.** Without the `UO` flag it is something else: an app error, an unready pod, or a route with no pods.
> - **Relying on flight logs after the fact.** They roll over. `upstream_rq_pending_overflow` keeps adding up.
> - **Mixing up `upstream_cx_overflow` and `upstream_rq_pending_overflow`.** The first is the connection limit, the second the waiting queue. They point at different settings.
> - **Forgetting the stats annotation.** Without `sidecar.istio.io/statsInclusionPrefixes` on the sender, the per-cluster counters are not there.

> *`UO` in the flight log and `upstream_rq_pending_overflow` in the counters set a shield refusal apart from an app `503`, and the app's silence confirms it.*

## Your mission: Circuit Breaking With Connection Pool Limits

You can now raise the shields, trip them on purpose, and prove a refusal with the `UO` flag and the overflow counters. Now prove it in a graded mission: cap how much work a sender may have open, and prove the shields refuse signals sent at the same time but never signals sent one by one.

The mission runs in its own training solar system, so first pause your playground. Nothing in it is lost:

```sh
astrona stop ats-014-playground-040-02
```

Then start the mission:

```sh
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-040/module-02/labs/lab-01
```

Read the task in [`question.md`](./labs/lab-01/question.md) and solve it on your own first. When you think you are done, send it for grading:

```sh
astrona submit -c sections/section-040/module-02/labs/lab-01
```

When the mission is done, remove it and wake your playground up again:

```sh
astrona destroy ats-014-lab-040-02
astrona start ats-014-playground-040-02
```
