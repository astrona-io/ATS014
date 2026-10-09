# Wrap-Up: Mission Debrief

Well flown, astronaut. You have finished every part and every mission in this module. Before you move on, look back at what you learned, check yourself, and land the playground cleanly.

## What you learned

This module was about the last of three decisions on a signal's path: which ship in a squadron takes it.

**From [Endpoint Selection And The `simple` Algorithms](./course-01-endpoint-selection-and-simple-algorithms.md):**

- The sender's proxy decides in order: the rule, the subset, then one ship. Picking the ship comes last.
- `simple` takes `LEAST_REQUEST` (the Istio default), `ROUND_ROBIN`, `RANDOM` or `PASSTHROUGH`. All of them spread signals; `PASSTHROUGH` switches the choice off.
- `istioctl proxy-config cluster ... -o json` shows the algorithm as `lbPolicy`. Round robin is Envoy's default, so it shows no `lbPolicy` line at all.

**From [`consistentHash` And The Ring](./course-02-consistent-hash-and-the-ring.md):**

- `consistentHash` is used instead of `simple`, never together. The same value always lands on the same ship.
- The ring stores nothing: the proxy works out the same hash every time. The proxy shows it as `RING_HASH`.
- Two values can collide on the same ship. That is normal.
- Stickiness is best effort: adding a ship rebuilt the ring and moved three of eight users.
- A signal with nothing to hash falls back to normal load balancing, with no error.

**From [Sticky Cookies And Other Hash Sources](./course-03-sticky-cookies-and-other-hash-sources.md):**

- `httpCookie` with `ttl` makes the sidecar hand out the cookie itself. Without `ttl`, no cookie is created.
- `useSourceIp` pins every signal from one address to one ship, which is a trap behind a gateway.
- `httpQueryParameterName` hashes a value in the URL. Quote such URLs in zsh.

**From [Policy Levels And Verification](./course-04-policy-levels-and-verification.md):**

- Port beats subset, and subset beats host.
- A subset inherits every `trafficPolicy` field it does not set, and replaces every field it does set as a whole.
- The cluster dump shows each subset's real `lbPolicy` and limits.

## Your missions

You proved each skill in a graded mission, right after the part that taught it:

| Mission | After the part | What you proved |
| --- | --- | --- |
| [Spread The Signals Evenly](./labs/lab-03/README.md) | Endpoint Selection And The `simple` Algorithms | replace a policy that sends everything to one ship with round robin |
| [Load Balancer Policy And Session Affinity](./labs/lab-01/README.md) | Policy Levels And Verification | keep one ship class sticky while another is spread evenly |
| [Session Affinity For Browsers](./labs/lab-02/README.md) | Policy Levels And Verification | hand browsers a sticky cookie, set on one port |

If you skipped one, go back to it now. The exam asks for exactly these skills.

## Check yourself

Try to answer each question before you open the answer.

<details>
<summary>1. Which proxy picks the ship for a signal?</summary>

The proxy of the ship that **sends** it. It picks after the rule and the subset are already chosen, from the list mission control gave it.
</details>

<details>
<summary>2. You set <code>simple: ROUND_ROBIN</code>, but the cluster dump shows no <code>lbPolicy</code> line. Is something wrong?</summary>

No. Round robin is Envoy's own default, and the dump leaves default values out. `LEAST_REQUEST` and `RANDOM` do show a line.
</details>

<details>
<summary>3. <code>alice</code> and <code>bob</code> land on the same ship under a header hash. Is the policy broken?</summary>

No. With a few ships, two values often collide on one. Try a third value: if it lands elsewhere, the hashing works.
</details>

<details>
<summary>4. You add a ship to a sticky squadron. What happens to your users?</summary>

Most stay where they were, but some move, because the ring is rebuilt. Stickiness is best effort, so an app that cannot lose its session needs shared session storage.
</details>

<details>
<summary>5. A policy hashes the <code>x-user</code> header. Signals without the header arrive. Where do they go?</summary>

They fall back to normal load balancing and spread over the squadron. There is no error.
</details>

<details>
<summary>6. Browsers send no special header. How do you keep each browser on one ship?</summary>

Hash a cookie with `httpCookie`, and give it a `ttl`. The `ttl` makes the sidecar hand out the cookie to a first-time visitor.
</details>

<details>
<summary>7. The host sets <code>connectionPool.tcp.maxConnections: 7</code>. Subset <code>v1</code> sets only a <code>loadBalancer</code>. Does v1 keep the limit?</summary>

Yes. A subset inherits every field it does not set. It would lose the limit only if it set its own `connectionPool`, because a field the subset sets replaces the host's whole field.
</details>

<details>
<summary>8. You want a user to stay on one version during a weighted split. Is stickiness the answer?</summary>

No. The subset is picked before the ship, for every signal. Stickiness only chooses among one subset's ships. Route by header in the flight plan instead.
</details>

## Clean up the playground

Your playground is a whole Kubernetes cluster running on your machine. When you are done with this module, remove it, and any mission that is still running.

First, see what is still running:

```sh
astrona list
```

Remove the playground. The command takes its **name**, not its folder path:

```sh
astrona destroy ats-014-playground-030-01
```

If `astrona list` also showed a mission, remove it the same way, for example:

```sh
astrona destroy ats-014-lab-030-02
```

Then check that everything is gone:

```sh
astrona list
```

```text
No astrona labs running.
```

You can start the playground again at any time with the `astrona run` command from the module's landing page. It always starts clean, so nothing you broke carries over.

> *The sender's proxy picks one ship for every signal: spread by an algorithm, or pinned by a hash. Whatever you choose, prove it in the cluster dump.*
