# Wrap-Up: Mission Debrief

Well flown, astronaut. You have finished every part and every mission in this module. Before you move on, look back at what you learned, check yourself, and land the playground cleanly.

## What you learned

This module was about the shields: the connection pool that makes a proxy refuse work it has no room for, at once, instead of letting signals pile up.

**From [The Connection Pool](./course-01-the-connection-pool.md):**

- The shields live in a `DestinationRule` under `trafficPolicy.connectionPool`.
- For HTTP/1, `tcp.maxConnections` (docking ports) and `http.http1MaxPendingRequests` (the holding orbit) form the breaker. A signal is refused only when both are full, and it is refused at once with `503`.
- The limits count signals **at the same time**. A one-at-a-time test never trips them.
- With only `maxConnections` set, the holding orbit is close to unlimited, so signals wait instead of being refused.

**From [Overflow And Its Signatures](./course-02-overflow-and-its-signatures.md):**

- A shield refusal carries the `UO` flag in the flight log, with `"-"` as the chosen ship.
- Most refusals happen in the sender's proxy. A few happen at the probe pod's own door, on its `inbound` side. The probe's app never sees a refused signal.
- `upstream_rq_pending_overflow` and `upstream_cx_overflow` count the refusals. They need the `sidecar.istio.io/statsInclusionPrefixes` annotation on the sender.

**From [Scope, Verification And Retry Amplification](./course-03-scope-verification-and-retry-amplification.md):**

- `istioctl proxy-config cluster` shows the live limits under `circuitBreakers`. Anything you do not set shows `4294967295`: no limit.
- The same limits apply on both ends: each sender caps what it sends, and each probe pod caps what it accepts.
- For HTTP/2 and gRPC, `http2MaxRequests` is the setting that matters.
- A sender's own `UO` refusals are never retried. The probe's real `5xx` answers are, so a large `attempts` with `retryOn: 5xx` multiplies the load on a struggling service.

## Your missions

You proved each skill in a graded mission, right after the part that taught it:

| Mission | After the part | What you proved |
| --- | --- | --- |
| [Circuit Breaking With Connection Pool Limits](./labs/lab-01/README.md) | Overflow And Its Signatures | raise the shields and prove they refuse signals sent at the same time |
| [Calm The Retry Storm](./labs/lab-02/README.md) | Scope, Verification And Retry Amplification | stop a retry policy from multiplying the load on a struggling probe |

If you skipped one, go back to it now. Each mission is short, and the exam asks for exactly these skills.

## Check yourself

Try to answer each question before you open the answer.

<details>
<summary>1. You set <code>maxConnections: 1</code> and send 100 signals one after another. How many are refused?</summary>

None. Only one signal is ever in flight, so the limit is never exceeded. The shields count signals at the same time, not signals in total.
</details>

<details>
<summary>2. A <code>DestinationRule</code> sets only <code>tcp.maxConnections: 1</code>. Fortio sends 3 signals at a time. What happens?</summary>

Every signal still gets through, a little slower. Without `http1MaxPendingRequests`, the holding orbit is close to unlimited, so extra signals wait instead of being refused.
</details>

<details>
<summary>3. The sender gets a <code>503</code>. How do you know it was the shields and not the app?</summary>

Read the sender's flight log. A shield refusal carries the `UO` flag and `overflow`, with `"-"` as the chosen ship. The `upstream_rq_pending_overflow` counter goes up too. An app's own `503` has no `UO` flag.
</details>

<details>
<summary>4. The probe's own flight log shows a <code>503 UO</code> on an <code>inbound</code> line. What happened?</summary>

The probe pod's proxy refused the signal at its door, because the same connection pool limits also apply to what each pod accepts. The probe's app never saw that signal.
</details>

<details>
<summary>5. <code>istioctl proxy-config cluster</code> shows <code>"maxRequests": 4294967295</code>. What does it mean?</summary>

That limit is not set, so there is no real limit. Only the settings you write are enforced.
</details>

<details>
<summary>6. Your service speaks gRPC. You set <code>maxConnections: 1</code>. Is the load limited?</summary>

Barely. gRPC runs on HTTP/2, where one connection carries many signals at once. For HTTP/2, set `http2MaxRequests`.
</details>

<details>
<summary>7. With <code>retryOn: 5xx</code> and <code>attempts: 3</code>, are the shields' own refusals retried?</summary>

No. A refusal in the sender's own proxy is never retried. But every `5xx` the probe sends back is, so each real failure can reach the probe four times.
</details>

<details>
<summary>8. You want retries only for signals that never reached the service. Which <code>retryOn</code> do you pick?</summary>

`connect-failure,refused-stream`. Both `5xx` and `gateway-error` also retry a `503` the service sent back.
</details>

## Clean up the playground

Your playground is a whole Kubernetes cluster running on your machine. When you are done with this module, remove it, and any mission that is still running.

First, see what is still running:

```sh
astrona list
```

Remove the playground. The command takes its **name**, not its folder path:

```sh
astrona destroy ats-014-playground-040-02
```

If `astrona list` also showed a mission, remove it the same way, for example:

```sh
astrona destroy ats-014-lab-040-02-02
```

Then check that everything is gone:

```sh
astrona list
```

```text
No astrona labs running.
```

You can start the playground again at any time with the `astrona run` command from the module's landing page. It always starts clean, so nothing you broke carries over.

> *A connection pool refuses work at once instead of letting it pile up. Both ends enforce it, and retries never rescue a refusal, but they do multiply every real failure.*
