# Wrap-Up: Mission Debrief

Well flown, astronaut. You have finished every part and every mission in this module. Before you move on, look back at what you learned, check yourself, and land the playground cleanly.

## What you learned

This module was about mirroring: sending a copy of every signal to a test ship while the proven ship keeps answering.

**From [Mirror As A Sibling Of Route](./course-01-mirror-as-a-sibling-of-route.md):**

- `mirror` sits next to `route` on the same `http` rule. It is one destination with no `weight`, and the copy is extra traffic on top of the split.
- The sender's answer always comes from the route. The shadow's answer, and its delay, are thrown away.
- A shadow that answers `503` to every copy is invisible from the sender's side.
- A mirror to a subset no `DestinationRule` defines silently sends nothing.

**From [Identifying And Sampling Shadow Traffic](./course-02-identifying-and-sampling-shadow-traffic.md):**

- Istio 1.30 sends the copy unchanged: no `-shadow` suffix on the host name.
- The proof is on the receiving ship: its flight log shows the copy coming in through the mirror subset, with the same request ID as the original in the sender's log.
- `mirrorPercentage` copies a random share of signals. Leave it out and the share is 100%.
- Count many signals before you judge a percentage.

**From [Consequences, Verification And Limits](./course-03-consequences-verification-and-limits.md):**

- The shadow does real work: database writes, messages, payments. Only its answer is thrown away.
- The sender's proxy holds the mirror as `requestMirrorPolicies`, with the share stored as a fraction of a million.
- A quiet mirror is one of three things: no policy, a policy naming an undefined subset (`IST0101`), or a subset with no pods (`IST0173`).
- With a split plus a mirror, the mirror target receives its own share plus a copy of everything.

## Your missions

You proved each skill in a graded mission, right after the part that taught it:

| Mission | After the part | What you proved |
| --- | --- | --- |
| [Mirror Live Traffic To A Shadow Service](./labs/lab-01/README.md) | Identifying And Sampling Shadow Traffic | send every answer from the stable version while the release candidate receives every copy |
| [Find The Quiet Shadow](./labs/lab-02/README.md) | Consequences, Verification And Limits | find and fix a mirror that sends nothing |

If you skipped one, go back to it now. Each mission is short, and the exam asks for exactly these skills.

## Check yourself

Try to answer each question before you open the answer.

<details>
<summary>1. A flight plan routes 100% of signals to v1 and mirrors to v2. Which version answers the sender?</summary>

v1, every time. The sender's answer always comes from the route. The mirror's answer is thrown away.
</details>

<details>
<summary>2. Where does <code>mirror</code> go in the YAML?</summary>

Next to `route`, on the same `http` rule. It is one destination, not a list, and it has no `weight`.
</details>

<details>
<summary>3. You leave <code>mirrorPercentage</code> out. What share of signals is copied?</summary>

All of them. The default is 100%, not 0%.
</details>

<details>
<summary>4. How do you prove a copy arrived, on Istio 1.30?</summary>

Look at the receiving ship's flight log. The copy comes in through the mirror subset, and it carries the same request ID as the original in the sender's log. Do not look for a `-shadow` suffix: Istio 1.30 does not add one.
</details>

<details>
<summary>5. A flight plan splits 50/50 between v1 and v2 and mirrors everything to v2. You send 20 signals. Roughly how many does v2 receive?</summary>

About 30: its own share of about 10, plus a copy of all 20. Size a mirror target for its share plus everything it copies.
</details>

<details>
<summary>6. The sender is happy, the shadow receives nothing, and <code>istioctl analyze</code> reports <code>IST0173</code>. What is wrong?</summary>

The mirror's subset selects no pods: its labels match no running ship. The mirror policy is present and correct, but the mirror cluster has no endpoints.
</details>

<details>
<summary>7. Why can mirroring be dangerous even though nobody sees the shadow's answer?</summary>

The shadow runs its full handler. Database writes, messages and payments really happen. Only the answer is thrown away.
</details>

<details>
<summary>8. You need to know whether a new version gives the same answers as the old one. Is mirroring the right tool?</summary>

No. Nothing ever looks at the shadow's answer, so mirroring cannot compare answers. It finds crashes and load problems, not wrong results.
</details>

## Clean up the playground

Your playground is a whole Kubernetes cluster running on your machine. When you are done with this module, remove it, and any mission that is still running.

First, see what is still running:

```sh
astrona list
```

Remove the playground. The command takes its **name**, not its folder path:

```sh
astrona destroy ats-014-playground-020-02
```

If `astrona list` also showed a mission, remove it the same way, for example:

```sh
astrona destroy ats-014-lab-020-02-02
```

Then check that everything is gone:

```sh
astrona list
```

```text
No astrona labs running.
```

You can start the playground again at any time with the `astrona run` command from the module's landing page. It always starts clean, so nothing you broke carries over.

> *A mirror sends a copy of every signal to a test ship. The proven ship answers, the copy's answer is thrown away, and the copy's work is real.*
