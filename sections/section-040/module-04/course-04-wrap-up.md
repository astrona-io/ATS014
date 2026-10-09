# Wrap-Up: Mission Debrief

Well flown, astronaut. You have finished every part and every mission in this module. Before you move on, look back at what you learned, check yourself, and land the playground cleanly.

## What you learned

This module was about orbits: keeping signals close to the sender, and moving them further away when the nearby ships fail.

**From [Where Locality Comes From](./course-01-where-locality-comes-from.md):**

- An endpoint's locality comes from its node's `topology.kubernetes.io/region` and `zone` labels, plus the optional `topology.istio.io/subzone`.
- The `istio-locality` pod label overrides the node's locality for one pod. Its value uses dots: `local.zone-b`.
- Check every endpoint's locality from the sender with `istioctl proxy-config endpoints ... -o json` before you configure anything.
- The sender needs a locality too: "nearby" is measured from the sending ship's orbit.

**From [Preference, `distribute` And `failover`](./course-02-preference-distribute-and-failover.md):**

- Istio only applies the locality preference to a host whose `DestinationRule` has `outlierDetection`. `localityLbSetting: {enabled: true}` on its own changes nothing.
- With outlier detection, the far zone's endpoints get `"priority": 1` and are only used when the nearby zone has nothing healthy left.
- `distribute` sets exact weights per sender orbit. They must add up to 100, and they work without outlier detection.
- `failover` names the next **region**, needs outlier detection, and cannot be combined with `distribute`.

**From [The Health Dependency And Scope](./course-03-the-health-dependency-and-scope.md):**

- Endpoint removal (a ship scaled to zero) falls back without losing a signal. Endpoint failure (a ship that answers `503` but stays ready) only fails over through outlier detection.
- With `consecutive5xxErrors: 2`, two signals fail, then the damaged ship is pulled out of formation and its `OUTLIER CHECK` shows `FAILED`.
- `maxEjectionPercent` must be high enough to eject the damaged ships.
- A mesh-wide `meshConfig.localityLbSetting` sets the standing policy; a `DestinationRule` overrides it for one host.

## Your missions

You proved each skill in a graded mission, right after the part that taught it:

| Mission | After the part | What you proved |
| --- | --- | --- |
| [Give Every Ship Its Orbit](./labs/lab-02/README.md) | Where Locality Comes From | find and fix a ship that sits in the wrong orbit |
| [Split Signals Between Two Orbits](./labs/lab-03/README.md) | Preference, `distribute` And `failover` | send exact shares of signals to two orbits with `distribute` |
| [Locality Load Balancing And Failover](./labs/lab-01/README.md) | The Health Dependency And Scope | make signals leave a damaged orbit through outlier detection |

If you skipped one, go back to it now. Each mission is short, and the exam asks for exactly these skills.

## Check yourself

Try to answer each question before you open the answer.

<details>
<summary>1. Your cluster has one node. How can two pods on it sit in two different zones?</summary>

With the `istio-locality` label on each pod template, for example `local.zone-a` and `local.zone-b`. It overrides the locality the pod would get from its node.
</details>

<details>
<summary>2. You write a <code>DestinationRule</code> with only <code>localityLbSetting: {enabled: true}</code>. Do signals stay in the sender's zone?</summary>

No. Istio only applies the locality preference to a host that has `outlierDetection`. Add an `outlierDetection` block, and the signals stay in the nearby zone.
</details>

<details>
<summary>3. How can you see, in the sender's proxy, that a zone is only a fallback?</summary>

In `istioctl proxy-config endpoints ... -o json`, the endpoints of the far zone carry `"priority": 1`. Priority 0, the sender's own zone, is used first.
</details>

<details>
<summary>4. Your <code>distribute</code> block sends 70 to <code>zone-a</code> and 20 to <code>zone-b</code>. What happens?</summary>

Istio rejects the object: `total locality weight 90 != 100`. The weights must add up to exactly 100.
</details>

<details>
<summary>5. Can you use <code>distribute</code> and <code>failover</code> together for one host?</summary>

No. Istio rejects it with `can not simultaneously specify 'distribute' and 'failover'`. Pick one.
</details>

<details>
<summary>6. You scale the nearby ship to zero, and every signal moves to the far zone. Have you proved that failover works?</summary>

No. That is endpoint removal: the endpoint left the list. Failover is about a ship that stays in the list while failing, and only outlier detection can notice that. Test it with a damaged ship.
</details>

<details>
<summary>7. Each zone has one ship, and <code>maxEjectionPercent</code> is left at its default. Why does failover never happen?</summary>

The default of 10% cannot eject even one of two endpoints. Nothing is ever marked unhealthy, so nothing ever fails over. Raise it, for example to `100`.
</details>

<details>
<summary>8. A ship is <code>2/2 Running</code> in <code>kubectl get pods</code>, yet signals avoid it. Where do you look?</summary>

At the sender's endpoint list: `istioctl proxy-config endpoints`. If its `OUTLIER CHECK` column says `FAILED`, outlier detection has pulled it out of formation.
</details>

## Clean up the playground

Your playground is a whole Kubernetes cluster running on your machine. When you are done with this module, remove it, and any mission that is still running.

First, see what is still running:

```sh
astrona list
```

Remove the playground. The command takes its **name**, not its folder path:

```sh
astrona destroy ats-014-playground-040-04
```

If `astrona list` also showed a mission, remove it the same way, for example:

```sh
astrona destroy ats-014-lab-040-04-03
```

Then check that everything is gone:

```sh
astrona list
```

```text
No astrona labs running.
```

You can start the playground again at any time with the `astrona run` command from the module's landing page. It always starts clean, so nothing you broke carries over.

> *Locality keeps signals close to the sender. Outlier detection decides which ships count as damaged, and only then can signals move to another orbit.*
