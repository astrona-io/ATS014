# Wrap-Up: Mission Debrief

Well flown, astronaut. You have finished every part and every mission in this module. Before you move on, look back at what you learned, check yourself, and land the playground cleanly.

## What you learned

This module was about simulation drills: faults that the communications officers fake on purpose, so you can see how your ships and your safety settings cope before a real ship fails.

**From [Slow A Ship Down](./course-01-slow-a-ship-down.md):**

- `fault.delay` holds a signal for `fixedDelay` and then sends it on. The sender still gets a correct answer, just late.
- The drill goes on the flight plan of the ship you pretend is struggling. The sender's communications officer carries it out.
- The sender's flight log marks the signal with `DI`. The receiver gets a normal signal, late, and its own timing is untouched.
- `percentage.value` is a percent: `0.1` is one signal in a thousand. Leave it out, and every matching signal gets the drill.

**From [Fail A Signal Before It Leaves](./course-02-fail-a-signal-before-it-leaves.md):**

- `fault.abort` answers the signal at once with the status you choose. The signal never leaves the sending ship.
- The receiver has no record of an aborted signal. The evidence is `FI` and `fault_filter_abort` in the sender's flight log.
- A delay and an abort can share one rule. They are separate coin tosses, and a signal that gets both is marked `DI,FI`.

**From [Scope A Drill To Your Own Signals](./course-03-scope-a-drill-to-your-own-signals.md):**

- Put the drill on a rule with a `match`, first, and keep a plain rule below it for everyone else.
- `headers` matches what a signal carries. `sourceLabels` matches the pod that sends it.
- A drill scoped on a label only works through a chain if the middle ship passes the label on.

**From [Drive Your Resilience Settings With Faults](./course-04-drive-your-resilience-settings-with-faults.md):**

- A delay longer than the caller's timeout makes the timeout fire: `504` with `UT` at the caller, `DI` one hop further.
- A rule with a `fault` ignores its own `timeout` and `retries`. Put the safety settings on the caller's route.
- An abort never reaches a ship, so it cannot test setting a failing ship aside.
- A forgotten drill shows up as `envoy.filters.http.fault` in the proxy's route orders.

## Your missions

You proved each skill in a graded mission, right after the part that taught it:

| Mission | After the part | What you proved |
| --- | --- | --- |
| [Run Two Simulation Drills](./labs/lab-02/README.md) | Fail A Signal Before It Leaves | slow one ship down and fail another, and leave the evidence in the right flight logs |
| [Stop The Drill That Never Ended](./labs/lab-03/README.md) | Scope A Drill To Your Own Signals | turn a drill that broke every signal into one that hits test signals only |
| [Fault Injection With Delays And Aborts](./labs/lab-01/README.md) | Drive Your Resilience Settings With Faults | add a delay and an abort for one test user, and make a timeout meet the delay |

If you skipped one, go back to it now. Each mission is short, and the exam asks for exactly these skills.

## Check yourself

Try to answer each question before you open the answer.

<details>
<summary>1. You add a 2-second <code>delay</code> at 100% to navcom. What status does the sender get?</summary>

A `200`, about two seconds late. A delay holds the signal and then sends it on, so the answer is still correct.
</details>

<details>
<summary>2. You want scout v2 to live with a slow navcom. Which flight plan gets the drill?</summary>

The one for navcom, the ship you pretend is struggling. Scout v2's communications officer carries it out, because scout v2 is the ship that sends the signal.
</details>

<details>
<summary>3. Half the signals to navcom fail with <code>500</code>. Navcom's flight log shows no <code>500</code> at all. Why?</summary>

The failures are an abort. The sender's communications officer answered them itself, so they never reached navcom. Look for `FI` in the sender's flight log.
</details>

<details>
<summary>4. A flight log line shows <code>503 DI,FI</code>. What happened to that signal?</summary>

It was first held back by the delay, and then aborted with a `503`. Both halves of the drill hit it.
</details>

<details>
<summary>5. Your drill rule matches <code>end-user: jason</code>, but it sits below a plain rule with no <code>match</code>. Who meets the drill?</summary>

Nobody. The plain rule fits every signal and is read first, so the drill rule is never reached.
</details>

<details>
<summary>6. How do you fail only the signals the scout sends to navcom, and not the shuttle's?</summary>

Put the abort on a navcom rule with `match: - sourceLabels: app: scout`, and a plain rule below it. `sourceLabels` matches the pod that sends the signal.
</details>

<details>
<summary>7. An abort at 50% and <code>retries: attempts: 3</code> sit on the same route. Why do about half the signals still fail?</summary>

A rule with a `fault` ignores its own `retries` and `timeout`. Navcom receives exactly one signal per success: no retry is ever sent.
</details>

<details>
<summary>8. Signals to navcom crawl, and nobody changed any ship. How do you check for a forgotten drill?</summary>

Look for `DI` or `FI` in the sender's flight log, run `kubectl get virtualservice -A`, and search the sender's route orders from `istioctl proxy-config routes` for `envoy.filters.http.fault`.
</details>

## Clean up the playground

Your playground is a whole Kubernetes cluster running on your machine. When you are done with this module, remove it, and any mission that is still running.

First, see what is still running:

```sh
astrona list
```

Remove the playground. The command takes its **name**, not its folder path:

```sh
astrona destroy ats-014-playground-050-01
```

If `astrona list` also showed a mission, remove it the same way, for example:

```sh
astrona destroy ats-014-lab-050-01-02
```

Then check that everything is gone:

```sh
astrona list
```

```text
No astrona labs running.
```

You can start the playground again at any time with the `astrona run` command from the module's landing page. It always starts clean, so nothing you broke carries over.

> *A drill fakes a failure so you can trust your safety settings. Aim it with a `match`, read it from the sender's flight log, and remove it when the test is done.*
