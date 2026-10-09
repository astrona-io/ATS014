# Wrap-Up: Mission Debrief

Well flown, astronaut. You have finished every part and the mission in this module. Before you move on, look back at what you learned, check yourself, and land the playground cleanly.

## What you learned

This module was about *when* your rules reach the fleet, not what they say. The same correct objects can still break signals if they arrive in the wrong order.

**From [The Order To Apply And Remove Rules](./course-01-the-order-to-apply-and-remove-rules.md):**

- The `VirtualService` and the `DestinationRule` are read by the sidecar of the ship that **sends** the signal. At the edge of the mesh, a gateway does that job instead.
- Apply in this order: `ServiceEntry`, then `DestinationRule`, then `Gateway`, then `VirtualService`. A `Sidecar` can go in any time, but check its `egress.hosts` list afterwards.
- "Make before break": if a `VirtualService` reaches a sidecar before the `DestinationRule` that defines its subset, the sidecar answers **`503 NC`** ("no cluster") by itself.
- `kubectl apply` returns when the object is stored, not when the proxies have it. Before you test, check the sender's `istioctl proxy-config clusters`, and run `istioctl analyze`.
- Remove in the reverse order: `VirtualService`, `Gateway`, `DestinationRule`, `ServiceEntry`. Remove the pointer first.

**From [One Object Per Host, And The Defaults](./course-02-one-object-per-host-and-the-defaults.md):**

- Two files with the same `metadata.name` in the same namespace describe the same object, so `kubectl apply` replaces it (`configured`). It never adds a second one.
- Keep one `VirtualService` and one `DestinationRule` per beacon. Two objects for one host have no defined order.
- With no rules at all, Istio has no HTTP timeout, retries connection errors 2 times but never an app's own `503`, uses `LEAST_REQUEST` load balancing, lets unknown outside hosts through (`ALLOW_ANY`), and has circuit breaker limits so high they are effectively unlimited.
- The response flag in the flight log names the problem: `NC`, `UH`, `UO` and `URX` all reach the sender as a `503`, so read the flag, not just the code.

## Your mission

You proved the order in a graded mission, right after the part that taught it:

| Mission | After the part | What you proved |
| --- | --- | --- |
| [Retire A Ship Class Safely](./labs/lab-01/README.md) | The Order To Apply And Remove Rules | retire a subset while a patrol ship keeps flying, without a single failed signal |

If you skipped it, go back to it now. Changing a live system without breaking it is exactly the habit the exam rewards.

## Check yourself

Try to answer each question before you open the answer.

<details>
<summary>1. You add subset <code>v2</code> and route signals to it. Which object do you apply first?</summary>

The `DestinationRule` that defines `v2`. Wait until the `v2` subset shows up in the sender's `istioctl proxy-config clusters`, then apply the `VirtualService` that routes to it.
</details>

<details>
<summary>2. You retire subset <code>v1</code>. Which object do you change first?</summary>

The `VirtualService`. Move every route off `v1`, check that the senders' proxies have the new flight plan, and only then remove `v1` from the `DestinationRule`.
</details>

<details>
<summary>3. You apply a <code>VirtualService</code> that routes to <code>v1</code> before any <code>DestinationRule</code> exists. What does the sender get, and what does the flight log say?</summary>

A `503`, and the flag `NC`, "no cluster". `istioctl analyze` reports `IST0101 Referenced host+subset in destinationrule not found`.
</details>

<details>
<summary>4. Your change looks fine on one test. Why can it still be wrong?</summary>

The gap between your `kubectl apply` and the moment every proxy has the new orders is short, so one test often lands after it. Under steady traffic, signals inside that gap still fail. Only the order prevents that.
</details>

<details>
<summary>5. You apply a second file with the same <code>metadata.name</code> and a different subset. How many <code>VirtualService</code> objects exist afterwards?</summary>

One. Same name, same namespace means the same object: `kubectl apply` says `configured` and replaces it.
</details>

<details>
<summary>6. A slow app takes 30 seconds to answer, and you wrote no rules. What happens to the sender?</summary>

It waits the full 30 seconds. Istio has no default HTTP timeout.
</details>

<details>
<summary>7. An app answers with its own <code>503</code>. Does Istio retry it by default?</summary>

No. The default retries cover connection errors only. In the flight log the flag is `-` and the status came `via_upstream`, and the app receives the signal exactly once.
</details>

<details>
<summary>8. Which object can you apply at any point in the order, and what must you check afterwards?</summary>

The `Sidecar` resource. Afterwards, check that every host your apps call is still in its `egress.hosts` list, or those signals stop working.
</details>

## Clean up the playground

Your playground is a whole Kubernetes cluster running on your machine. When you are done with this module, remove it, and the mission if it is still running.

First, see what is still running:

```sh
astrona list
```

Remove the playground. The command takes its **name**, not its folder path:

```sh
astrona destroy ats-014-playground-010-03
```

If `astrona list` also showed the mission, remove it the same way:

```sh
astrona destroy ats-014-lab-010-03-01
```

Then check that everything is gone:

```sh
astrona list
```

```text
No astrona labs running.
```

You can start the playground again at any time with the `astrona run` command from the module's landing page. It always starts clean, so nothing you broke carries over.

> *Create the thing that is pointed at first. Remove the pointer first. And check that the orders arrived before you trust a test.*
