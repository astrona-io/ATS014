# Overview: Mirror Live Traffic To A Shadow Service (Playground)

> Declared in [`../config.yaml`](../config.yaml) under `metadata.docs.guide`.

Welcome aboard, astronaut. This is a **playground**, not a lab: a training
solar system in the simulator. It starts, installs Istio and a test
service, and then waits for you. There is no task, no `astrona submit` and no
pass or fail. Try things, break things, `astrona destroy`, start over.

## What's in the box

- A single-node `kind` Kubernetes cluster. `astrona run` points `kubectl` at it
  (context `kind-astro-ats-014-playground-020-02`).
- **Istio 1.30.5**, installed with Helm: `istio-base` (the CRDs) and `istiod`.
  There is no ingress or egress gateway. You need `istioctl` on your own
  machine for the `istioctl` commands.
- Namespace **`starfleet`**, labelled `istio-injection=enabled`, with:
  - **`probe`**, the echo probe that sends back what it receives, on port `8000`, in two versions: `probe-v1` and
    `probe-v2`, both behind one Service. `/hostname` returns the name of the
    pod that answered.
  - `shuttle`, your test client inside the mesh. You send every test signal from it.
- Access logs are on for the whole mesh, so each sidecar writes one line per
  request. Each sidecar is the communications officer on its ship, and this is the
  ship's black box flight log.
- **No DestinationRule and no VirtualService.** You write both in the module.

This playground has no bridge or scout ships. Mirroring is easiest to see on
the probe, so that is all it installs.

Every pod shows `2/2`: the app plus its `istio-proxy` sidecar.

## The helpers used in this module

Paste this block once in each new terminal:

- `mark_start` – run it before a test. It notes the start time.
- `count_received` – run it after a test. It counts what each version
  **received** since the start time. It reads this from the app's own log.
- `send_requests` – sends N requests (5 if you give no number) and shows which
  version **answered**.

```sh
mark_start() { M=$(date -u +%Y-%m-%dT%H:%M:%SZ); }
count_received()  { sleep 3; for v in v1 v2; do
  echo "probe-$v received: $(kubectl logs -n starfleet deploy/probe-$v -c probe --since-time=$M | grep -c 'GET /hostname')"
done; }
send_requests() { for i in $(seq 1 ${1:-5}); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s http://probe:8000/hostname | grep -o 'probe-v[0-9]'
done | sort | uniq -c; }
```

## Ready-made YAML

The folder [`../examples/`](../examples/) holds the files the module uses, in
the order you apply them. If you cloned the repository, apply them from there.
Otherwise the course parts show each one, ready to write to a file.

| File | What it does |
| --- | --- |
| `01-destinationrule-probe-subsets.yaml` | Subsets `v1` and `v2` for `probe` |
| `02-virtualservice-probe-v1-only.yaml` | Baseline: all traffic to v1, nothing mirrored |
| `03-virtualservice-probe-mirror-v2.yaml` | All traffic to v1, and a copy of every request to v2 |
| `cases/c1-…-mirror-20-percent.yaml` | Copy only 20% of requests |
| `cases/c2-probe-broken-pod.yaml` | A pod that always answers 503, labelled `version: broken` |
| `cases/c2-destinationrule-with-broken-subset.yaml` | Subsets `v1`, `v2` and `broken` |
| `cases/c2-virtualservice-mirror-to-broken.yaml` | Mirror everything into the broken pod |
| `cases/c3-…-split-and-mirror.yaml` | A 50/50 split plus a mirror to v2 |

## Things to try

- Route all traffic to v1 with no mirror. "Answered" and "received" match.
- Add a mirror to v2. Callers still only see v1, but v2 receives every request.
- Lower `mirrorPercentage` to 20 and count what v2 receives over 30 requests.
- Mirror into the broken pod. Callers still get `200`, while the broken pod
  answers `503` to every copy.
- Combine a 50/50 split with a mirror to v2, and work out how many requests v2
  receives in total.
- Point the mirror at a subset no DestinationRule defines, and see that
  nothing complains.

## Exam-style practice

Try the drill in [`practice.md`](practice.md). It has a checked solution.

## Start over without a new cluster

```sh
kubectl delete virtualservice,destinationrule --all -n starfleet
kubectl delete deployment probe-broken -n starfleet --ignore-not-found
```

## When you're done

```sh
astrona destroy ats-014-playground-020-02
```

`astrona destroy` takes the environment name, not the configuration path.
