# Wrap-Up: Mission Debrief

Well flown, astronaut. You have finished every part and every mission in this module. Before you move on, look back at what you learned, check yourself, and land the playground cleanly.

## What you learned

This module was about one field on the flight plan, `weight`, and everything around it: how the split is made, how to move it safely, and how to prove it.

**From [Weighted Destinations](./course-01-weighted-destinations.md):**

- A weighted route lists several destinations. `weight` sits next to `destination`, not inside it, and the weights should add up to 100.
- The sending ship's proxy makes one random pick for every signal. The share only shows up over many signals, and it is never exact.
- On Istio 1.30.5, weights that do not add up to 100 are accepted and used as a ratio: 50 + 30 gives about 62/38.
- `weight: 0` keeps a destination in your YAML, but the proxy's route leaves it out.
- A weight on a subset that does not exist is accepted, and those signals fail with `503`. `istioctl analyze` reports `IST0101`.

**From [Running A Rollout](./course-02-running-a-rollout.md):**

- A canary is the same `VirtualService` applied again with new numbers. A rollback is the old numbers, applied again, and lands in seconds.
- Count at least 100 signals before you trust a split.
- A merge patch on `spec.http` replaces the whole list, so it must restate every rule.
- A rule with a header match above the weighted rule takes those signals out of the split.

**From [Weight Versus Replicas, And Proof](./course-03-weight-versus-replicas-and-proof.md):**

- Weights control traffic share, replicas control capacity. Four v1 pods against one v3 pod still split 50/50.
- The weighted pick happens before load balancing, so the pod count cannot change it.
- `istioctl proxy-config routes` shows the weights the proxy holds, in a `weightedClusters` block.

## Your missions

You proved each skill in a graded mission, right after the part that taught it:

| Mission | After the part | What you proved |
| --- | --- | --- |
| [Split The Scout Three Ways](./labs/lab-02/README.md) | Weighted Destinations | split one beacon between three ship classes in exact shares |
| [Shift Traffic With Weighted Routing](./labs/lab-01/README.md) | Weight Versus Replicas, And Proof | run a canary with testers pinned above the split, without touching replica counts |

If you skipped one, go back to it now. Each mission is short, and the exam asks for exactly these skills.

## Check yourself

Try to answer each question before you open the answer.

<details>
<summary>1. Where does <code>weight</code> go in a route?</summary>

On the route item, next to `destination`, not inside it. If you nest it inside `destination`, Kubernetes rejects the object.
</details>

<details>
<summary>2. You set 80/20 and count 10 signals. All 10 go to v1. Is the flight plan broken?</summary>

No. Each signal is a separate random roll, and 10 out of 10 on v1 happens about one time in ten at 80/20. Count at least 100 signals before you judge the split.
</details>

<details>
<summary>3. You write weights 50 and 30. What happens?</summary>

Istio 1.30.5 accepts them without a warning and uses them as a ratio: about 62% and 38%. Still write weights that add up to 100.
</details>

<details>
<summary>4. How do you roll back a canary?</summary>

Apply the old numbers again, for example a flight plan with only the v1 destination. It is one `kubectl apply`, it lands in seconds, and no pod restarts.
</details>

<details>
<summary>5. You patch <code>spec.http</code> with a merge patch that lists only the weighted route. What happens to a header rule that was above it?</summary>

It is gone. A merge patch replaces the whole `http` list. Restate every rule in the patch, or use `kubectl apply` with the complete object.
</details>

<details>
<summary>6. jason's rule sends him to v3, above a 90/10 split between v1 and v2. Does jason count towards the 90/10?</summary>

No. The first rule that fits wins, so jason's signals never reach the weighted rule. The 90/10 only applies to everyone else.
</details>

<details>
<summary>7. v1 runs 4 pods and v3 runs 1 pod, at 50/50. What share does v3 get?</summary>

About 50%. The weight picks the subset first. Only then does load balancing pick a pod inside it, so the pod count changes capacity, not share.
</details>

<details>
<summary>8. Your split looks wrong. How do you check whether the proxy even has your weights?</summary>

Run `istioctl proxy-config routes deploy/shuttle -n starfleet --name 9080 -o json` and look at the `weightedClusters` block. If it is missing or old, the flight plan has not reached the proxy yet.
</details>

## Clean up the playground

Your playground is a whole Kubernetes cluster running on your machine. When you are done with this module, remove it, and any mission that is still running.

First, see what is still running:

```sh
astrona list
```

Remove the playground. The command takes its **name**, not its folder path:

```sh
astrona destroy ats-014-playground-020-01
```

If `astrona list` also showed a mission, remove it the same way, for example:

```sh
astrona destroy ats-014-lab-020-01
```

Then check that everything is gone:

```sh
astrona list
```

```text
No astrona labs running.
```

You can start the playground again at any time with the `astrona run` command from the module's landing page. It always starts clean, so nothing you broke carries over.

> *A weight decides the share, a rollback is one apply away, and the proxy's route table is where you prove it.*
