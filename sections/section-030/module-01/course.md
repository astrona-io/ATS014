# Load Balancer Policy And Session Affinity

<!-- astrona:playground -->
> [!NOTE]
> 🧪 **Hands-on playground for this module** — a clean, throwaway machine to explore on. No task, no grading. Folder: [`playground/`](https://github.com/astrona-io/ATS014/tree/main/sections/section-030/module-01/playground)
>
> ```sh
> astrona run --git ssh://git@github.com/astrona-io/ATS014.git -c sections/section-030/module-01/playground
> astrona destroy ats-014-playground-030-01
> ```

Every routing decision so far has ended at a *subset* — a group of pods. Something still has to pick one specific pod out of that group for each request, and until now you have let Istio decide. This module is about taking that decision over.

There are two reasons to. The first is efficiency: when requests have very different costs, plain round robin sends an expensive request to a pod that is already busy. The second is stickiness: some applications keep per-user state in memory, and a user whose requests bounce between three pods sees a broken session. Both live in the same field of the same object.

> `loadBalancer` in a `DestinationRule` decides how the client proxy picks an endpoint; `consistentHash` is how you get sticky sessions.

## How this module is organised

1. **[Endpoint Selection And The `simple` Algorithms](./course-01-endpoint-selection-and-simple-algorithms.md)** — where in the request path the choice happens, the four `simple` values and what each is for, and how to observe which endpoint a proxy actually chose.
2. **[`consistentHash` And The Ring](./course-02-consistent-hash-and-the-ring.md)** — the four things you can hash, how a hash becomes an endpoint, why affinity is best effort by design, and what happens to a request with nothing to hash.
3. **[Policy Levels And Verification](./course-03-policy-levels-and-verification.md)** — host, subset and port level settings and which wins, why a subset policy replaces rather than merges, and reading `lbPolicy` from a live proxy.

## Learning objectives

After this module you can:

- Explain where endpoint selection happens relative to routing and weighted cluster selection.
- Set `trafficPolicy.loadBalancer.simple` and say what `ROUND_ROBIN`, `LEAST_REQUEST`, `RANDOM` and `PASSTHROUGH` each do, and when each is the right choice.
- Configure session affinity with `consistentHash` over a header, a cookie, a query parameter or the source IP.
- Explain the ring-hash mechanism well enough to predict what happens to sessions when the endpoint set changes.
- Predict the behaviour of a request that does not carry the hashed property.
- Apply a `trafficPolicy` at host, subset or port level and say which one wins, and why a subset policy does not inherit the rest of the host's.
- Read `lbPolicy` and the ring hash configuration out of a live proxy with `istioctl proxy-config cluster`.

## Before you start

You need `DestinationRule` from section 010 — this module adds a second field to the object you already use for subsets. No new object is introduced, which is why this section has one module rather than three.

The playground gives you a single-node `kind` cluster with **Istio 1.30.5 already installed** (the `demo` profile) and the namespace **`lb-demo`**, injected, containing:

- `httpbin` — a Deployment with **three replicas**, behind a Service on port 8000 (container port 8080). Three endpoints is the minimum that makes endpoint selection observable; with one replica you cannot tell affinity from luck.
- `tester` — a client pod with `curl`.

No `DestinationRule` exists yet, so the mesh default policy is in force.

## Where this fits

`trafficPolicy` is the container for every client-side decision about a destination, and this module fills in one of its keys. Section 040 fills in three more on the same object — `connectionPool` for circuit breaking, `outlierDetection` for passive health checking, and `localityLbSetting` nested inside `loadBalancer` itself for locality preference. The precedence rules you learn in Part 3 apply to all of them, so it is worth getting them right here.
