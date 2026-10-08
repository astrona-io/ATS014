# Wrap-Up: Mission Debrief

Well flown, astronaut. Before your graded mission, take five minutes to look back at what you learned, check yourself, and land the playground cleanly.

## What you learned

This module was about the star chart each communications officer carries, and how to hand a ship a smaller one with the `Sidecar` resource.

**From [What A Proxy Is Programmed With](./course-01-what-a-proxy-is-programmed-with.md):**

- By default, `istiod` pushes the whole registry to every proxy: every Service in every namespace, whether or not the workload ever calls it. `istioctl proxy-config cluster deploy/tester -n sidecar-demo | wc -l` shows how much one proxy carries.
- A change is swapped into a running proxy over a long-lived xDS stream. No pod is restarted.
- The cost grows as **N × M**: N proxies, each holding about M entries for the whole mesh. It shows up as proxy memory, control plane CPU and push latency.
- Istio cannot work out on its own which services a workload calls, because the call graph is decided at runtime. Scoping is a declaration you make.
- The registry holds more than Kubernetes Services: `ServiceEntry` and `WorkloadEntry` hosts are in it too, and scoping applies to all of them.

**From [The Sidecar Object And Its Host Language](./course-02-the-sidecar-object-and-host-language.md):**

- A `Sidecar` with no `workloadSelector` applies to every workload in its own namespace. With a selector, it applies only to the matching pods in that namespace.
- `egress[].hosts` entries are always `<namespace>/<host>`. `./*` means the proxy's own namespace, `*/*` means everything, and the namespace half names where the *target* lives.
- `./*` and `istio-system/*` are the floor of every namespace-wide `Sidecar`. Leaving `istio-system/*` out breaks things partially and quietly.
- Scoping shrinks clusters and listeners together, and you can prove it with `proxy-config` without sending any traffic.
- A merge patch replaces the whole `hosts` list. Restate every entry you want to keep.
- A host reaches a proxy only if two gates open: the object's `exportTo` and the consumer's `Sidecar`.

**From [Precedence, Reachability And What It Is Not](./course-03-precedence-reachability-and-limits.md):**

- Precedence runs: a `Sidecar` with a matching `workloadSelector`, then the namespace default, then the root-namespace default (`istio-system`), then no scoping. The first match wins and **replaces** the others; nothing merges.
- Use at most one namespace-wide `Sidecar` per namespace, and never let two selectors match the same pod.
- A root-namespace `Sidecar` is the Death Star setting: one object narrows every unscoped namespace in the mesh at once.
- When a host is scoped away, the call fails (`000`, or `502` depending on `outboundTrafficPolicy`) and `proxy-config cluster` has no entry for it.
- `Sidecar` is a configuration control, not a security boundary. Use `AuthorizationPolicy` to deny calls on the server side, and `NetworkPolicy` to block traffic at the network layer.

## Check yourself

Try to answer each question before you open the answer.

<details>
<summary>1. You apply a new <code>Sidecar</code>. Do you need to restart the pods for it to take effect?</summary>

No. `istiod` pushes the new configuration to the running proxies over xDS, and it takes effect in seconds. If nothing changed, check the selector and the namespace, not the pod.
</details>

<details>
<summary>2. In a <code>Sidecar</code> in <code>sidecar-demo</code>, what does the entry <code>sidecar-other/*</code> select?</summary>

Every host in the `sidecar-other` namespace. The namespace half names where the target host lives, not where the `Sidecar` lives.
</details>

<details>
<summary>3. A namespace default lists <code>./*</code> and <code>istio-system/*</code>. You add a selective <code>Sidecar</code> for <code>app: tester</code> that lists only <code>./*</code>. Does <code>tester</code> still see <code>istio-system</code>?</summary>

No. The selective `Sidecar` wins and replaces the namespace default for the pods it selects. It inherits nothing, so `tester` gets only `./*`.
</details>

<details>
<summary>4. How do you prove a scoping change worked without sending any traffic?</summary>

Read the proxy's own configuration: `istioctl proxy-config cluster deploy/tester -n sidecar-demo | wc -l` should drop, and a `grep` for the scoped-away namespace should print nothing.
</details>

<details>
<summary>5. A task says one workload "must not be able to" call another. Is a <code>Sidecar</code> enough?</summary>

No. `Sidecar` only decides what a proxy knows. A process that bypasses the proxy, or a pod without a sidecar, is not affected. To enforce it, combine it with `AuthorizationPolicy` (enforced on the server side) or a Kubernetes `NetworkPolicy`.
</details>

## Clean up the playground

The playground is a whole Kubernetes cluster running on your machine. The graded lab builds its own, separate cluster. Remove the playground first, so the two do not compete for memory and you cannot send a command to the wrong solar system by accident.

**Step 1.** Destroy the playground. The command takes the playground's **name**, not its folder path:

```sh
astrona destroy ats-014-playground-010-02
```

**Step 2.** Check that it is gone:

```sh
astrona list
```

`ats-014-playground-010-02` should no longer be in the list.

> [!TIP]
> You can start the playground again at any time with the same `astrona run` command from the module's landing page. It always starts clean, so nothing you broke carries over.

## Your next mission

You are ready for the lab: [Scope Proxy Configuration With The Sidecar Resource](./labs/lab-01/README.md). You will cut `sidecar-demo` down to its own namespace, `istio-system` and `sidecar-other`, and prove that `sidecar-third` is gone from the proxy and can no longer be reached.

Start the lab:

```sh
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-010/module-02/labs/lab-01
```

Read the task in [`question.md`](./labs/lab-01/question.md) and try it on your own first. When you think you are done, send it for grading:

```sh
astrona submit -c sections/section-010/module-02/labs/lab-01
```

The grader reads the proxy's configuration dump and sends live traffic, so keep [Precedence, Reachability And What It Is Not](./course-03-precedence-reachability-and-limits.md) open next to it.
