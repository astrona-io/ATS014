# Load Balancer Policy And Session Affinity

<!-- astrona:playground -->
> [!NOTE]
> 🧪 **Hands-on playground for this module** — a clean, throwaway machine to explore on. No task, no grading. Folder: `playground/`
>
> ```sh
> astrona run --git ssh://git@github.com/astrona-io/ATS014.git -c sections/section-030/module-01/playground
> astrona destroy ats-014-playground-030-01
> ```

Astronaut, every routing decision so far has ended at a *subset*: a named group of pods. Think of a subset as one ship class. A ship class often has several spaceships (pods) in its squadron, and each signal (request) goes to just one of them. Something still has to pick that one ship. Until now you let Istio decide. On this mission you take that decision over.

The flight plan (the `VirtualService`) gets a signal to the right squadron. Then someone still has to say which ship in the squadron takes it. Choosing that ship is **load balancing**: spreading the work over the pods.

There are two reasons to control it:

- **Efficiency.** Some requests cost much more than others. Plain turn-taking can send a heavy request to a pod that is already busy.
- **Stickiness.** Some apps keep each user's data in memory. If a user's requests jump between three pods, that user sees a broken session. Stickiness (session affinity) means the same astronaut always reaches the same ship.

Both are set in the same field of the same object:

> `loadBalancer` in a `DestinationRule` decides how the calling proxy picks a pod. `consistentHash` is how you get sticky sessions.

## How this module is organised

1. **[Endpoint Selection And The `simple` Algorithms](./course-01-endpoint-selection-and-simple-algorithms.md)** — where in the request path the choice happens, the four `simple` values and what each is for, and how to see which pod a proxy actually chose.
2. **[`consistentHash` And The Ring](./course-02-consistent-hash-and-the-ring.md)** — the four things you can hash, how a hash becomes a pod, why stickiness is "best effort", and what happens to a request with nothing to hash.
3. **[Policy Levels And Verification](./course-03-policy-levels-and-verification.md)** — settings at host, subset and port level and which one wins, why a subset policy replaces the host policy instead of merging with it, and how to read `lbPolicy` from a live proxy.

## Learning objectives

After this module you can:

- Explain where endpoint selection happens compared with routing and weighted subset selection.
- Set `trafficPolicy.loadBalancer.simple` and say what `ROUND_ROBIN`, `LEAST_REQUEST`, `RANDOM` and `PASSTHROUGH` each do, and when each is the right choice.
- Configure session affinity with `consistentHash` over a header, a cookie, a query parameter or the source IP.
- Explain the ring-hash mechanism well enough to predict what happens to sessions when pods are added or removed.
- Predict the behaviour of a request that does not carry the hashed property.
- Explain why stickiness does not keep a user on one version in a weighted split.
- Apply a `trafficPolicy` at host, subset or port level and say which one wins, and why a subset policy does not inherit the rest of the host's.
- Read `lbPolicy` and the ring hash configuration out of a live proxy with `istioctl proxy-config cluster`.

## Before you start

This module assumes [section 000](../../section-000/module-01/course.md): a proxy beside every pod, `istiod` programming it, and `istioctl proxy-config` as the way to see what a proxy really holds.

You also need the `DestinationRule` from section 010. This module adds a second field to the object you already use for subsets. It adds no new object, which is why this section has one module.

The playground gives you a single-node `kind` cluster with **Istio 1.30.5** installed with Helm (`istio-base` and `istiod`), and access logs switched on for every proxy. Namespace **`bookinfo`** has sidecar injection on and contains:

- `httpbin` — a test server behind one Service on port `8000`, with **four pods**: three of `httpbin-v1` and one of `httpbin-v2`. The path `/hostname` answers with the name of the pod that served you. With only one pod you could not tell stickiness from luck, so the playground gives you several.
- `curl` — a client pod inside the mesh. You send every test request from it.

No `DestinationRule` exists yet, so Istio's default policy is in force. It is your training solar system: break it and launch a new one whenever you like. [Part 1](./course-01-endpoint-selection-and-simple-algorithms.md) gives you a small helper, `count_pods`, that every "Try it" in this module uses. The playground's [overview](./playground/docs/overview.md) has the same helper, ideas to try, and an exam-style [practice task](./playground/docs/practice.md).

The graded labs for this module run in their own environment and are described in their own `question.md`.

## Where this fits

`trafficPolicy` holds every decision the caller makes about a destination, and this module fills in one of its keys. Section 040 fills in three more on the same object: `connectionPool` for circuit breaking, `outlierDetection` for taking faulty pods out of service, and `localityLbSetting` (inside `loadBalancer` itself) for preferring nearby pods. The precedence rules in Part 3 apply to all of them, so it is worth getting them right here.
