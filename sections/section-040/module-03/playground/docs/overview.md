# Overview: Outlier Detection And Endpoint Ejection (Playground)

Welcome aboard, astronaut. This is a **playground**, your training solar system, not a mission. The cluster starts, installs Istio, deploys the
ships below, and then waits. There is no task, no `astrona submit` and no pass/fail.
Explore, break things, `astrona destroy`, start over.

## What's in the box

- A single-node `kind` cluster: a small solar system of your own. `astrona run` points `kubectl` at it
  (context `kind-astro-ats-014-playground-040-03`).
- **Istio 1.30.5**, installed with Helm: `istio-base` (the CRDs) and `istiod` (mission
  control, which sends every communications officer its orders). No ingress or egress gateway.
- Flight logs switched on for the whole mesh (`bootstrap/manifests/access-logs.yaml`),
  so every proxy writes one line per signal.
- The planet (namespace) **`starfleet`**, labelled `istio-injection=enabled`, holding:
  - `probe-v1` and `probe-v2`: two healthy ships of the echo probe, both behind one
    Service `probe` on port `8000`. The `/get` path answers `200`.
  - `shuttle`: the client you send single signals from. Its communications officer keeps the
    per-destination `outlier_detection.*` counters (`sidecar.istio.io/statsInclusionPrefixes`).
  - `fortio`: a load generator, for the full circuit breaker and the practice task.
- Every pod shows `2/2`: the ship plus its `istio-proxy` communications officer.
- **No broken ship and no `DestinationRule` yet.** Adding the broken ship is the first
  step of the module, so you see the problem before the fix.

## Helpers

Paste these once per terminal. The module's parts and the practice task use them.

```sh
# 15 single signals from the shuttle to the probe, counted by status code
count_status() { for i in $(seq 1 15); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" http://probe:8000/get
done | sort | uniq -c; }
# the probe's endpoints as the shuttle's proxy sees them, with the OUTLIER CHECK column
show_endpoints() { istioctl proxy-config endpoints deploy/shuttle -n starfleet --cluster "outbound|8000||probe.starfleet.svc.cluster.local"; }
# the shuttle proxy's outlier-detection counters for the probe
ejection_stats() { kubectl exec -n starfleet deploy/shuttle -c istio-proxy -- \
  pilot-agent request GET stats 2>/dev/null | grep -E 'probe.starfleet.*outlier_detection.ejections_(active|total|enforced_consecutive_5xx):'; }
# 30 signals to the probe over N parallel connections, from fortio
load_test() { kubectl exec -n starfleet deploy/fortio -c fortio -- \
  fortio load -c "$1" -qps 0 -n 30 -loglevel Warning http://probe:8000/get 2>&1 | grep -E "^Code"; }
```

## Example files

If you cloned the repository, the YAML is in [`../examples/`](../examples/). Apply it from
the `playground/` folder, in this order:

| File | What it shows |
| --- | --- |
| `examples/01-probe-broken.yaml` | A third ship behind `probe` that answers `503` to everything. `count_status` shows about a third failing. |
| `examples/02-destinationrule-probe-outlier-detection.yaml` | Eject after 3 errors in a row, at most half the ships. The second `count_status` round is clean. |
| `examples/cases/c1-probe-broken-500.yaml` + `c1-destinationrule-probe-gateway-errors-only.yaml` | A ship that answers **500**, and a rule that only counts 502/503/504. The ship is never ejected. |
| `examples/cases/c2-destinationrule-probe-full-circuit-breaker.yaml` | Connection pool and outlier detection in one rule. `load_test 3` overflows. |
| `examples/cases/c3-destinationrule-probe-10-percent.yaml` | The 10% default trap: the broken ship is found but never ejected. `ejections_overflow` counts the blocked attempts. |

## Things to try

- Add the broken ship, run `count_status`, then apply the `02-` rule and run it twice.
- Compare `kubectl get endpointslices -n starfleet -l kubernetes.io/service-name=probe` with
  `show_endpoints`. Kubernetes and the proxy disagree, and that disagreement is the feature.
- Restart `deploy/shuttle` for a clean slate, apply the `c3-` rule, and confirm nothing is
  ever ejected with three ships.
- Watch `ejections_active` flip between 1 and 0 while `ejections_total` only climbs.
- Set `minHealthPercent: 70` and explain why the broken ship gets signals again after
  the first ejection.
- Compare the shuttle's `show_endpoints` with the same command against `deploy/fortio`.
  Each proxy has its own verdict.
- Do the practice task: [practice.md](practice.md).

## Start over without a new cluster

```sh
kubectl delete destinationrule --all -n starfleet
kubectl delete deploy probe-broken probe-broken-500 -n starfleet --ignore-not-found
```

## When you're done

```sh
astrona destroy ats-014-playground-040-03
```

(`astrona destroy` takes the environment name, not the configuration path.)
