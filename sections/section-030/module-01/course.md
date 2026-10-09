# Load Balancer Policy And Session Affinity

Astronaut, a flight plan sends a signal to the right ship class. But a ship class is often a whole squadron: several spaceships (pods) built the same way. Each signal still goes to just one of them, and something has to pick which one. Until now you let Istio decide. On this mission you take that decision over.

Picking the ship is called **load balancing**: spreading the work over the pods. There are two reasons to control it:

- **Efficiency.** Some signals cost much more than others. Plain turn-taking can send a heavy signal to a ship that is already busy.
- **Stickiness.** Some apps keep each user's data in memory. If one user's signals jump between three ships, that user sees a broken session. **Stickiness**, or **session affinity**, means the same astronaut always reaches the same ship.

Both are set in the same place: the `loadBalancer` field of a `DestinationRule`, the docking instructions for a beacon.

## Learning objectives

After this module you can:

- Explain where picking a ship happens, compared with matching a rule and picking a subset.
- Set `trafficPolicy.loadBalancer.simple` and say what `ROUND_ROBIN`, `LEAST_REQUEST`, `RANDOM` and `PASSTHROUGH` each do, and when each is the right choice.
- Configure session affinity with `consistentHash` over a header, a cookie, a query parameter or the source IP.
- Predict what happens to sticky sessions when ships are added or removed, and to a signal that carries nothing to hash.
- Explain why stickiness does not keep a user on one version in a weighted split.
- Set a `trafficPolicy` at host, subset or port level, and say exactly which settings a subset inherits from the host and which it loses.
- Read `lbPolicy` and the ring settings from a live proxy with `istioctl proxy-config cluster`.

## Before you start

Every mission starts with a pre-flight check, astronaut. Make sure you have the knowledge this module expects, know what is in your playground, and have one helper ready in your terminal.

### What you should already know

- **How the mesh works.** A proxy (the communications officer) sits beside every pod, and `istiod` (mission control) sends it orders. You can read those orders with `istioctl proxy-config`.
- **Docking instructions.** A `DestinationRule` defines subsets (ship classes) by pod labels. This module adds a second field to that same object: no new object.

### What is in your playground

Your playground is a small training solar system: one `kind` cluster with **Istio 1.30.5** installed with Helm, and flight logs (access logs) switched on for every proxy. Everything lives on the planet **`starfleet`**:

| Ship | Its role |
| --- | --- |
| `probe` v1 (3 pods), `probe` v2 (1 pod) | A squadron of four echo probes behind one Service on port `8000`. The path `/hostname` answers with the name of the pod that served the signal |
| `shuttle` | Your client. You send every test signal from here |

With only one pod you could not tell stickiness from luck, so the probe squadron has four. There is **no** `DestinationRule` yet, so Istio's default load balancer is in force.

Launch your playground now, and keep it running next to you while you read the parts:

<!-- astrona:playground -->

### One helper to paste first

Paste this into each new terminal. It sends 8 signals from the shuttle to the probe and counts which pod answered each one. Any `curl` options you add, such as a header, are passed on:

```sh
count_pods() { for i in $(seq 1 8); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s "$@" | grep -o '"probe-[^"]*"'
done | sort | uniq -c; }
HOSTNAME_URL=http://probe:8000/hostname
```

Use it like this: `count_pods $HOSTNAME_URL`, or `count_pods -H "x-user: alice" $HOSTNAME_URL`.

### Extra practice

The playground also comes with an exam-style practice task with a checked solution, in its `docs/practice.md`.
