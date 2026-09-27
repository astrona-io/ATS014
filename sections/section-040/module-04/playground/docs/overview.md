# Overview: Locality Load Balancing And Failover (Playground)

> Declared in [`../config.yaml`](../config.yaml) under `metadata.docs.guide`.

This is a **playground**, not a lab. The environment starts clean, runs
`bootstrap/prepare.sh`, applies the starting workloads, and then waits. There is
no task, no `astrona submit`, and no pass/fail. Explore, break things,
`astrona destroy`, start over.

## What's in the box

- A single-node `kind` Kubernetes cluster with `kubectl` already pointed at it.
- **Istio 1.30.5** (`demo` profile) and `istioctl` on your PATH.
- Namespace **`locality-demo`**, injected, containing:
  - `httpbin-zone-a` and `httpbin-zone-b` — one replica each, behind one
    `httpbin` Service on port 8000.
  - `tester` — a client pod with `curl`.
- **No `DestinationRule`.**

### One adaptation to be aware of

Locality normally comes from the **node** a pod runs on, which needs a
multi-node cluster with different `topology.kubernetes.io/zone` labels. This
playground has one node, so `manifests/lab-start.yaml` declares locality
directly with the **`istio-locality` pod label** (`local.zone-a`,
`local.zone-b`) — a documented Istio override for exactly this situation. The
matching lab under `domains/` uses node affinity and expects a real multi-node
cluster.

Everything about `localityLbSetting` behaves identically here. What this
playground **cannot** show you is real cross-zone latency or cost, because both
pods are on the same machine.

## Things to try

- Confirm both endpoints carry a locality before anything else:
  `istioctl proxy-config endpoints deploy/tester -n locality-demo --cluster "outbound|8000||httpbin.locality-demo.svc.cluster.local" -o json | grep -E '"region"|"zone"'`.
  An empty locality means nothing below will work.
- Send traffic with no `DestinationRule` at all and see that Istio already
  prefers the caller's locality. Most of the default behaviour needs no config.
- Scale `httpbin-zone-a` to 0 and watch traffic move with no failed requests —
  that is endpoint removal, not failover.
- Add `outlierDetection` and make the local pod fail instead (for example by
  deleting its container's listening port with a `kubectl exec`, or by swapping
  the image for one that 503s) to see health-driven failover.
- Remove `outlierDetection` from a working failover setup and confirm failover
  stops happening. This is the examinable fact.
- Set an explicit 70/30 `distribute` from `local/zone-a/*` and measure the split
  over 100 requests.
- Try `distribute` and `failover` in the same `localityLbSetting` and read the
  rejection.

## When you're done

```sh
astrona destroy ats-014-playground-040-04
```

(`astrona destroy` takes the environment name, not the config path.)
