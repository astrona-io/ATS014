# Wrap-Up: Mission Debrief

Well flown, astronaut. You have finished every part and every mission in this module. Before you move on, look back at what you learned, check yourself, and land the playground cleanly.

## What you learned

This module was about the star chart each ship carries, and the `Sidecar` resource that makes it smaller.

**From [Every Ship Carries The Whole Star Chart](./course-01-every-ship-carries-the-whole-star-chart.md):**

- By default, mission control (`istiod`) gives every proxy a destination for every Service on every planet, whether or not the ship ever calls it.
- New orders reach running proxies over open streams. No pod restarts.
- The cost grows as proxies × destinations: proxy memory, mission control CPU and push delay.
- The default also means every ship can reach every beacon. Nobody allowed that; it is a side effect.

**From [Give A Ship A Smaller Star Chart](./course-02-give-a-ship-a-smaller-star-chart.md):**

- A `Sidecar` has four fields: `workloadSelector`, `egress[].hosts`, `outboundTrafficPolicy` and `ingress`. Without a selector it applies to every ship on its planet.
- Hosts are written `<namespace>/<host>`. `./*` is the ship's own planet, and `./*` plus `istio-system/*` is the floor of every planet-wide `Sidecar`.
- Scoping is proved without traffic: the destination and its listener disappear from `istioctl proxy-config`.
- Under the default `ALLOW_ANY`, a signal for an uncharted host still leaves through `PassthroughCluster`. With `outboundTrafficPolicy: REGISTRY_ONLY` it falls into the `BlackHoleCluster` (`000`, flag `UH`).
- A host can be filtered in two places: the owner's `exportTo` and the receiving planet's `Sidecar`.

**From [Which Star Chart A Ship Uses](./course-03-which-star-chart-a-ship-uses.md):**

- Order of precedence: selector `Sidecar`, then planet `Sidecar`, then the root `Sidecar` in `istio-system`.
- The winner replaces the rest completely, including `istio-system/*` and `outboundTrafficPolicy`. It never merges.
- One planet default plus non-overlapping selectors is the only defined shape.
- A root `Sidecar` narrows every unscoped planet at once; its `./*` means each ship's own planet.

**From [A Star Chart Is Not A Shield](./course-04-a-star-chart-is-not-a-shield.md):**

- A `Sidecar` decides what a ship knows. It does nothing for a pod without a sidecar, and never limits who may call a planet.
- For enforcement, combine it with `REGISTRY_ONLY`, `AuthorizationPolicy` and `NetworkPolicy`.
- When a host is missing from a proxy, check selector, planet and root `Sidecar` in that order, then `exportTo`.

## Your missions

You proved each skill in a graded mission, right after the part that taught it:

| Mission | After the part | What you proved |
| --- | --- | --- |
| [Scope Proxy Configuration With The Sidecar Resource](./labs/lab-01/README.md) | Give A Ship A Smaller Star Chart | cut a planet's star chart down and keep a third planet out of reach |
| [Fix One Ship's Star Chart](./labs/lab-02/README.md) | Which Star Chart A Ship Uses | repair a selector `Sidecar` that inherited nothing |

If you skipped one, go back to it now. Each mission is short, and the exam asks for exactly these skills.

## Check yourself

Try to answer each question before you open the answer.

<details>
<summary>1. A fresh mesh has no <code>Sidecar</code> anywhere. Which Services does the shuttle's proxy know about?</summary>

All of them, on every planet. Mission control gives every proxy the whole star chart by default.
</details>

<details>
<summary>2. You change a <code>Sidecar</code>. Do the affected pods need a restart?</summary>

No. Mission control pushes the new orders to the running proxies over their open streams. The change takes effect within seconds.
</details>

<details>
<summary>3. In a <code>Sidecar</code> on <code>starfleet</code>, what does <code>outpost/*</code> select?</summary>

Every host on the `outpost` planet. The namespace half names where the *target* lives, not where the `Sidecar` lives.
</details>

<details>
<summary>4. Why does almost every planet-wide <code>Sidecar</code> list <code>istio-system/*</code>?</summary>

Because the proxy needs mission control, which lives in `istio-system`, for its own work. Leave it out and something fails partly, with nothing pointing at the `Sidecar`.
</details>

<details>
<summary>5. The probe is off the shuttle's star chart, but the call still answers <code>200</code>. Why?</summary>

The mesh uses `ALLOW_ANY`, so the signal leaves through `PassthroughCluster` as raw bytes. Set `outboundTrafficPolicy` to `REGISTRY_ONLY` on the `Sidecar` to send it to the black hole instead.
</details>

<details>
<summary>6. A planet default lists <code>./*</code>, <code>istio-system/*</code> and <code>outpost/*</code>. You add a selector <code>Sidecar</code> for the shuttle that lists only <code>./*</code>. Does the shuttle still see <code>outpost</code>?</summary>

No. The selector `Sidecar` replaces the planet default for the shuttle. It inherits nothing, so the shuttle sees only its own planet.
</details>

<details>
<summary>7. How do you prove scoping worked without sending any signal?</summary>

Read the proxy's own orders: the host is missing from `istioctl proxy-config cluster`, the cluster count has dropped, and the listener for that port is gone.
</details>

<details>
<summary>8. Can a <code>Sidecar</code> stop a pod without a sidecar from calling your planet?</summary>

No. A `Sidecar` only shapes what proxies are told, and it never limits incoming signals. Use an `AuthorizationPolicy` on the receiving side, or a `NetworkPolicy`.
</details>

## Clean up the playground

Your playground is a whole Kubernetes cluster running on your machine. When you are done with this module, remove it, and any mission that is still running.

First, see what is still running:

```sh
astrona list
```

Remove the playground. The command takes its **name**, not its folder path:

```sh
astrona destroy ats-014-playground-010-02
```

If `astrona list` also showed a mission, remove it the same way, for example:

```sh
astrona destroy ats-014-lab-010-02-02
```

Then check that everything is gone:

```sh
astrona list
```

```text
No astrona labs running.
```

You can start the playground again at any time with the `astrona run` command from the module's landing page. It always starts clean, so nothing you broke carries over.

> *A `Sidecar` gives a ship a smaller star chart. The closest one wins, it never merges, and it decides what a ship knows, not what a planet accepts.*
