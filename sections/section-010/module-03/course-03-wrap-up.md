# Wrap-Up: Mission Debrief

Well flown, astronaut. Before you head to the section capstone, look back at what you learned, check yourself, and land the playground cleanly.

## What you learned

This module was about *when* your rules reach the fleet, not what they say. The same correct objects can still break signals if they arrive in the wrong order.

**From [The Order To Apply And Remove Rules](./course-01-the-order-to-apply-and-remove-rules.md):**

- The `VirtualService` and the `DestinationRule` run in the sidecar of the app that **makes** the call. At the edge of the mesh, a gateway does that job instead.
- Apply in this order: `ServiceEntry`, then `DestinationRule`, then `Gateway`, then `VirtualService`. A `Sidecar` can go in any time, but check its `egress.hosts` list afterwards.
- "Make before break": if a `VirtualService` reaches a sidecar before the `DestinationRule` that defines its subset, the sidecar answers **`503 NC`** ("no cluster") by itself.
- `kubectl apply` returns when the object is stored, not when the proxies have it. Check `istioctl proxy-status` (every proxy `SYNCED`) and `istioctl analyze -n starfleet` before you test.
- Remove in the reverse order: `VirtualService`, `Gateway`, `DestinationRule`, `ServiceEntry`. Remove the pointer first.

**From [One Object Per Host, And The Defaults](./course-02-one-object-per-host-and-the-defaults.md):**

- Two files with the same `metadata.name` in the same namespace describe the same object, so `kubectl apply` replaces it. It does not add a second one.
- Keep one `VirtualService` and one `DestinationRule` per host. Two objects for one host have no defined order, so you cannot say which rule wins.
- With no rules at all, Istio has no HTTP timeout, retries connection errors 2 times (not an app's own `503`), uses `LEAST_REQUEST` load balancing, lets unknown outside hosts through (`ALLOW_ANY`), and has circuit breaker limits so high they are effectively unlimited.
- The response flag in the access log (the ship's black box flight log) names the problem: `NC`, `UH`, `UO` and `URX` all reach the caller as a `503`, so read the flag, not just the code.

## Check yourself

Try to answer each question before you open the answer.

<details>
<summary>1. You add subset <code>v2</code> and route traffic to it. Which object do you apply first?</summary>

The `DestinationRule` that defines `v2`. Wait until `istioctl proxy-status` shows every proxy as `SYNCED`, then apply the `VirtualService` that routes to `v2`.
</details>

<details>
<summary>2. A call fails with <code>503</code> and the flag <code>NC</code>, but both objects look correct. What happened?</summary>

The route reached the sidecar before the subset it points at, or the `DestinationRule` was removed while the route still used it. Nothing is wrong with either object: only the order was.
</details>

<details>
<summary>3. You want to stop using a version. What do you remove first?</summary>

Stop routing to it in the `VirtualService` first. Wait for the push, then remove the subset from the `DestinationRule`.
</details>

<details>
<summary>4. You apply a second file with the same <code>metadata.name</code> and namespace. How many objects do you have now?</summary>

One. `kubectl apply` replaces the object and says `configured`, not `created`.
</details>

<details>
<summary>5. With no <code>VirtualService</code>, a call to the <code>probe</code>'s <code>/delay/3</code> takes about 3 seconds. Why does nothing cut it short?</summary>

Istio has no default HTTP timeout. A request waits as long as the app takes, until you set a `timeout` (section 040).
</details>

## Clean up the playground

The playground is a whole Kubernetes cluster running on your machine. The capstone builds its own, separate cluster. Remove the playground first, so the two do not compete for memory and you cannot send a command to the wrong solar system by accident.

**Step 1.** Destroy the playground. The command takes the playground's **name**, not its folder path:

```sh
astrona destroy ats-014-playground-010-03
```

**Step 2.** Check that it is gone:

```sh
astrona list
```

`ats-014-playground-010-03` should no longer be in the list.

> [!TIP]
> You can start the playground again at any time with the same `astrona run` command from the module's landing page. It always starts clean, so nothing you broke carries over.

## Your next mission

This module has no graded lab of its own. Your next mission is the section 010 capstone: [Route And Scope A Storefront](../capstone/labs/lab-01/README.md). It combines routing from module 01 and scoping from module 02. The grader does not check the order you apply things in, but use the order from this module anyway: it is the habit that keeps a real system from failing while you change it.

Start the capstone:

```sh
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-010/capstone/labs/lab-01
```

Read the task in [`question.md`](../capstone/labs/lab-01/question.md) and try it on your own first. When you think you are done, send it for grading:

```sh
astrona submit -c sections/section-010/capstone/labs/lab-01
```
