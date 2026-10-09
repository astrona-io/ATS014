# Wrap-Up: Mission Debrief

Well flown, astronaut. You have finished every part and every mission in this module. Before you move on, look back at what you learned, check yourself, and land the playground cleanly.

## What you learned

This module was about outlier detection: the sender's communications officer pulling a ship out of formation because of the answers it gets, not because of anything the ship says about itself.

**From [Passive Health Checking](./course-01-passive-health-checking.md):**

- A readiness probe is **active**: the ship answers a question about itself. A ship with a dead dependency passes it and still fails every real signal.
- Outlier detection is **passive**: each sender's proxy watches the answers it already gets. Something has to fail before anything is detected.
- The settings live in a `DestinationRule`, under `trafficPolicy.outlierDetection`.
- `consecutive5xxErrors` counts 5xx answers **in a row, per endpoint**. One success from that ship resets its count, so a ship that fails only sometimes may never be caught.

**From [Ejection Mechanics And Limits](./course-02-ejection-mechanics-and-limits.md):**

- A consecutive-error ejection happens at once. `interval` is the sweep that lets ships back in after their time is over.
- The ejection lasts `baseEjectionTime` × the number of ejections, capped by Envoy at 300 seconds (or `baseEjectionTime`, if larger).
- `consecutive5xxErrors` is **5** as soon as an `outlierDetection` block exists. To count only `502`, `503` and `504` with `consecutiveGatewayErrors`, set `consecutive5xxErrors: 0`.
- `maxEjectionPercent` defaults to **10%**. With three ships, one ejection is 33%, so nothing is ever ejected. `ejections_overflow` counts the blocked attempts.
- `minHealthPercent` switches detection off when the healthy share drops below it. Its default is `0%`.

**From [Local, Temporary, And Verified](./course-03-local-temporary-and-verified.md):**

- Every proxy reaches its own verdict. The shuttle can see a ship as `FAILED` while fortio sees it as `OK`.
- Kubernetes never changes: the EndpointSlice still lists the ejected pod, and `STATUS` stays `HEALTHY`. Only the `OUTLIER CHECK` column shows the ejection.
- `ejections_active`, `ejections_total` and `ejections_enforced_consecutive_5xx` prove an ejection. They need the `sidecar.istio.io/statsInclusionPrefixes` annotation.
- A ship that stays broken gives a cycle of ejections with growing gaps, not a steady state.
- A connection pool and outlier detection together, in **one** `DestinationRule`, make a full circuit breaker.

## Your missions

You proved each skill in a graded mission, right after the part that taught it:

| Mission | After the part | What you proved |
| --- | --- | --- |
| [Outlier Detection And Endpoint Ejection](./labs/lab-01/README.md) | Ejection Mechanics And Limits | eject a failing ship while Kubernetes still lists it |
| [Raise Both Shields](./labs/lab-02/README.md) | Local, Temporary, And Verified | combine a connection pool and outlier detection, and prove both halves |

If you skipped one, go back to it now. Each mission is short, and the exam asks for exactly these skills.

## Check yourself

Try to answer each question before you open the answer.

<details>
<summary>1. A pod is <code>2/2 Running</code> and passes its readiness probe, yet answers every signal with <code>503</code>. Does Kubernetes take it out of the Service?</summary>

No. Kubernetes only looks at labels and readiness, never at real answers. Outlier detection in the sender's proxy is what catches this ship.
</details>

<details>
<summary>2. You write an <code>outlierDetection</code> block with only <code>consecutiveGatewayErrors: 3</code>. A ship answers <code>500</code> to everything. Is it ejected?</summary>

Yes, after five `500`s in a row. `consecutive5xxErrors` is 5 as soon as the block exists, and a `500` counts for it. Set `consecutive5xxErrors: 0` to count only gateway errors.
</details>

<details>
<summary>3. Your rule has <code>consecutive5xxErrors: 3</code>, the probe has three ships, and the broken one is never ejected. What do you check first?</summary>

`maxEjectionPercent`. At its 10% default, ejecting one ship of three (33%) is never allowed. Read `ejections_overflow` in the sender's stats: anything above 0 confirms it. Raise the limit to at least 34.
</details>

<details>
<summary>4. <code>baseEjectionTime</code> is <code>1m</code>. The same ship is ejected for the third time. How long does it stay out?</summary>

About three minutes: `baseEjectionTime` × the number of ejections, plus up to one `interval` until the next sweep lets it back.
</details>

<details>
<summary>5. The shuttle's proxy shows the broken ship as <code>FAILED</code>. Is fortio protected too?</summary>

Not by the shuttle's verdict. Every proxy decides on its own, from the answers it got. Fortio's proxy ejects the ship only after it has seen enough failures itself.
</details>

<details>
<summary>6. Where do you see an ejection: <code>kubectl get endpointslices</code> or <code>istioctl proxy-config endpoints</code>?</summary>

Only in `istioctl proxy-config endpoints`, in the `OUTLIER CHECK` column of the sender's proxy. The EndpointSlice still lists the pod.
</details>

<details>
<summary>7. <code>ejections_active</code> reads <code>0</code> but <code>ejections_total</code> reads <code>2</code>. Is outlier detection broken?</summary>

No. The ship was ejected twice, and its last ejection just ended. If it is still broken, it fails again and is ejected for longer. `total` only goes up, `active` flips between `1` and `0`.
</details>

<details>
<summary>8. You want to limit open signals to the probe and remove failing ships. One <code>DestinationRule</code> or two?</summary>

One. Put `connectionPool` and `outlierDetection` side by side under the same `trafficPolicy`. Two rules for the same host do not combine reliably.
</details>

## Clean up the playground

Your playground is a whole Kubernetes cluster running on your machine. When you are done with this module, remove it, and any mission that is still running.

First, see what is still running:

```sh
astrona list
```

Remove the playground. The command takes its **name**, not its folder path:

```sh
astrona destroy ats-014-playground-040-03
```

If `astrona list` also showed a mission, remove it the same way, for example:

```sh
astrona destroy ats-014-lab-040-03-02
```

Then check that everything is gone:

```sh
astrona list
```

```text
No astrona labs running.
```

You can start the playground again at any time with the `astrona run` command from the module's landing page. It always starts clean, so nothing you broke carries over.

> *Outlier detection trusts the answers, not the ship: each sender's proxy pulls a failing ship out of formation on its own, and Kubernetes never notices.*
