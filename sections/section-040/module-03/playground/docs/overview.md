# Overview: Outlier Detection And Endpoint Ejection (Playground)

> Declared in [`../config.yaml`](../config.yaml) under `metadata.docs.guide`.

Welcome aboard, astronaut. This is a **playground**, your training solar system, not a lab. The cluster starts, installs Istio, deploys the
apps below, and then waits. There is no task, no `astrona submit` and no pass/fail.
Explore, break things, `astrona destroy`, start over.

## What's in the box

- A single-node `kind` cluster: a small solar system of your own. `astrona run` points `kubectl` at it
  (context `kind-astro-ats-014-playground-040-03`).
- **Istio 1.30.5**, installed with Helm: `istio-base` (the CRDs) and `istiod` (mission
  control, which sends every sidecar its orders). No ingress or egress gateway.
- Access logs switched on for the whole mesh (`bootstrap/manifests/access-logs.yaml`),
  so every sidecar writes one flight-log line per request.
- Namespace **`bookinfo`**, labelled `istio-injection=enabled`, containing:
  - `httpbin-v1` and `httpbin-v2` — two healthy pods of a small test server, both
    behind one Service `httpbin` on port `8000`.
  - `curl` — a client pod. Its sidecar keeps the per-cluster
    `outlier_detection.*` counters (`sidecar.istio.io/statsInclusionPrefixes`).
  - `fortio` — a load generator, for the full circuit breaker and the practice task.
- Every pod shows `2/2`: the app plus its `istio-proxy` sidecar.
- **No broken pod and no `DestinationRule` yet.** Adding the broken pod is the first
  step of the module, so you see the problem before the fix.

## Helpers

Paste these once per terminal. The module's parts and the practice task use them.

```sh
# 15 single requests from curl to httpbin, counted by status code
count_status() { for i in $(seq 1 15); do
  kubectl exec -n bookinfo deploy/curl -- curl -s -o /dev/null -w "%{http_code}\n" http://httpbin:8000/get
done | sort | uniq -c; }
# httpbin endpoints as the curl sidecar sees them, with the OUTLIER CHECK column
show_endpoints() { istioctl proxy-config endpoints deploy/curl -n bookinfo --cluster "outbound|8000||httpbin.bookinfo.svc.cluster.local"; }
# The curl sidecar's outlier-detection counters for httpbin
ejection_stats() { kubectl exec -n bookinfo deploy/curl -c istio-proxy -- \
  pilot-agent request GET stats | grep -E 'httpbin.bookinfo.*outlier_detection.ejections_(active|total|enforced_consecutive_5xx)'; }
# 30 requests to httpbin over N parallel connections, from fortio
load_test() { kubectl exec -n bookinfo deploy/fortio -c fortio -- \
  fortio load -c "$1" -qps 0 -n 30 -loglevel Warning http://httpbin:8000/get 2>&1 | grep -E "^Code"; }
```

## Example files

If you cloned the repository, the YAML is in [`../examples/`](../examples/). Apply it from
the `playground/` folder, in this order:

| File | What it shows |
| --- | --- |
| `examples/01-httpbin-broken-pod.yaml` | A third pod behind `httpbin` that answers 503 to everything. `count_status` shows about a third failing. |
| `examples/02-destinationrule-httpbin-outlier-detection.yaml` | Eject after 3 errors in a row, for 1 minute, at most half the pool. The failures stop. |
| `examples/cases/c1-httpbin-broken-500-pod.yaml` + `c1-destinationrule-gateway-errors-only.yaml` | A pod that answers **500**, and a rule that only counts 502/503/504. The pod is never ejected. |
| `examples/cases/c2-destinationrule-full-circuit-breaker.yaml` | Connection pool and outlier detection in one rule. `load_test 3` overflows. |

## Things to try

- Add the broken pod, run `count_status`, then apply the `02-` rule and run it twice.
- Compare `kubectl get endpoints httpbin -n bookinfo` with `show_endpoints`. Kubernetes
  and the proxy disagree, and that disagreement is the feature.
- Patch `maxEjectionPercent` to `10` (restart `deploy/curl` first for a clean slate) and
  confirm nothing is ever ejected with three endpoints.
- Watch `ejections_active` flip between 1 and 0 while `ejections_total` only climbs.
- Set `minHealthPercent: 70` and explain why the broken pod gets traffic again after
  the first ejection.
- Add a VirtualService with retries on top, and confirm the caller stops seeing
  failures while the proxy still ejects the bad pod.
- Do the exam-style drill: [practice.md](practice.md).

## Start over without a new cluster

```sh
kubectl delete destinationrule,virtualservice --all -n bookinfo
kubectl delete deploy httpbin-broken httpbin-broken-500 -n bookinfo --ignore-not-found
```

## When you're done

```sh
astrona destroy ats-014-playground-040-03
```

(`astrona destroy` takes the environment name, not the configuration path.)
