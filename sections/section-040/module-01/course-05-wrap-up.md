# Wrap-Up: Mission Debrief

Well flown, astronaut. You have finished every part and every mission in this module. Before you move on, look back at what you learned, check yourself, and land the playground cleanly.

## What you learned

This module was about the two settings that decide how long a sender waits and how often it tries again: the route `timeout` (the abort window) and `retries` (re-sending lost signals).

**From [Set An Abort Window](./course-01-set-an-abort-window.md):**

- Istio sets no HTTP timeout unless you write one. A slow ship makes every sender wait.
- `timeout` sits on one rule of a `VirtualService`. The sender's own sidecar measures it.
- When the abort window runs out, the sender's sidecar answers `504` itself. The flight log marks it with the flag `UT`.

**From [Test A Timeout Across Two Ships](./course-02-test-a-timeout-across-two-ships.md):**

- Put the delay on the ship being called, and the abort window on the caller.
- A timeout frees the sender, but the receiver keeps working: scout v2 still waited the full 2 seconds for navcom.
- A rule with a `fault` ignores its own `timeout` and `retries`.

**From [Re-Send Lost Signals](./course-03-re-send-lost-signals.md):**

- `attempts` counts retries after the first try: `attempts: 3` means up to four signals.
- `retryOn` decides which failures are re-sent: `5xx`, `gateway-error`, an exact code like `"503"`, and connection problems.
- A rule with no `retries` block still re-sends twice on connection problems, but not the app's own `503`. Only `attempts: 0` switches retries off.
- Count re-sends in the receiver's flight log. The sender's log marks used-up retries with `URX`.

**From [Share One Clock, Retry What Is Safe](./course-04-share-one-clock-and-retry-what-is-safe.md):**

- The route `timeout` covers every try together. It must be at least `(attempts + 1) × perTryTimeout`.
- A try that runs past `perTryTimeout` is re-sent with `retryOn: 5xx`, and the flight log shows `URX,UT`.
- `istioctl proxy-config routes` shows both settings as Envoy holds them: `timeout`, `retryOn`, `numRetries`, `perTryTimeout`.
- A retried `POST` is a second `POST`. Retry only signals that are safe to send twice, for example with a `method` match.

## Your missions

You proved each skill in a graded mission, right after the part that taught it:

| Mission | After the part | What you proved |
| --- | --- | --- |
| [Free The Shuttle From A Slow Navcom](./labs/lab-02/README.md) | Test A Timeout Across Two Ships | move an abort window from the delayed rule to the caller, where it really fires |
| [Retry Only The Signals Worth Re-Sending](./labs/lab-03/README.md) | Re-Send Lost Signals | narrow a retry policy to one status code, and count the re-sends at the receiver |
| [Timeouts And Retries](./labs/lab-01/README.md) | Share One Clock, Retry What Is Safe | give a write path no retries and a read path retries that fit their abort window |

If you skipped one, go back to it now. Each mission is short, and the exam asks for exactly these skills.

## Check yourself

Try to answer each question before you open the answer.

<details>
<summary>1. A flight plan has no <code>timeout</code>. How long does a sender wait for a ship that never answers?</summary>

As long as it takes, possibly forever. Istio sets no HTTP timeout unless you write one.
</details>

<details>
<summary>2. The sender gets a <code>504</code>. The flight log shows <code>UT</code>. Who made the <code>504</code>?</summary>

The sender's own sidecar. Its abort window ran out, so it cancelled the signal and answered `504` itself. The receiver never answered.
</details>

<details>
<summary>3. You put a 2-second delay and a 0.5-second <code>timeout</code> on the same rule. What does the sender see?</summary>

A `200` after about 2 seconds. A rule with a `fault` ignores its own `timeout`. Put the delay on the ship being called and the timeout on the caller.
</details>

<details>
<summary>4. Your timeout fires after 0.5 seconds. Does the receiver stop working?</summary>

No. The timeout only frees the sender. The receiver finishes its work and answers on a connection that was already given up.
</details>

<details>
<summary>5. A rule has <code>attempts: 3</code>. How many signals can reach the receiver for one failing request?</summary>

Four: the first try plus three retries.
</details>

<details>
<summary>6. You removed the <code>retries</code> block. Are retries off now?</summary>

No. The default policy still re-sends twice on connection problems. Only `attempts: 0` switches retries off. The default does not re-send the app's own `503`.
</details>

<details>
<summary>7. <code>attempts: 3</code>, <code>perTryTimeout: 1s</code>, <code>timeout: 1.5s</code>. A slow signal gets a <code>504</code> after 1.5 seconds. Why?</summary>

The abort window covers every try. Four tries of 1 second need at least 4 seconds, but the window is 1.5 seconds, so the retries are cut short after the second try.
</details>

<details>
<summary>8. Why should a <code>POST</code> usually not be retried?</summary>

Because a retried `POST` is a second `POST`. If the first try did the work and only the answer was lost, the retry does the work again. Retry only signals that are safe to send twice.
</details>

## Clean up the playground

Your playground is a whole Kubernetes cluster running on your machine. When you are done with this module, remove it, and any mission that is still running.

First, see what is still running:

```sh
astrona list
```

Remove the playground. The command takes its **name**, not its folder path:

```sh
astrona destroy ats-014-playground-040-01
```

If `astrona list` also showed a mission, remove it the same way, for example:

```sh
astrona destroy ats-014-lab-040-01
```

Then check that everything is gone:

```sh
astrona list
```

```text
No astrona labs running.
```

You can start the playground again at any time with the `astrona run` command from the module's landing page. It always starts clean, so nothing you broke carries over.

> *The abort window decides how long a sender waits, and the retry policy decides how often it tries again. Both share one clock, and only safe signals deserve a second try.*
