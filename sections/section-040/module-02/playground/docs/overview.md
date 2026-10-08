# Overview: Circuit Breaking With Connection Pool Limits (Playground)

> Declared in [`../config.yaml`](../config.yaml) under `metadata.docs.guide`.

Welcome aboard, astronaut. This is a **playground**, your training solar system, not a lab. The cluster starts, installs Istio, deploys the
apps below, and then waits. There is no task, no `astrona submit` and no pass/fail.
Explore, break things, `astrona destroy`, start over.

## What's in the box

- A single-node `kind` cluster: a small solar system of your own. `astrona run` points `kubectl` at it
  (context `kind-astro-ats-014-playground-040-02`).
- **Istio 1.30.5**, installed with Helm: `istio-base` (the CRDs) and `istiod` (mission
  control, which sends every sidecar its orders). No ingress or egress gateway.
- Access logs switched on for the whole mesh (`bootstrap/manifests/access-logs.yaml`),
  so every sidecar writes one flight-log line per request.
- Namespace **`bookinfo`**, labelled `istio-injection=enabled`, containing:
  - `httpbin-v1` and `httpbin-v2` — a small test server, both behind one Service
    `httpbin` on port `8000`.
  - `fortio` — a load generator that sends many requests at the same time. Its pod
    has the `sidecar.istio.io/statsInclusionPrefixes: "cluster.outbound"`
    annotation, so its sidecar keeps the circuit-breaker counters.
  - `curl` — a client pod for single requests.
- Every pod shows `2/2`: the app plus its `istio-proxy` sidecar.
- **No `DestinationRule`**, so there is no limit yet.

## Helpers

Paste these once per terminal. The module's parts use them.

```sh
# 30 requests to httpbin over N parallel connections, from fortio; prints the status-code summary
load_test() { kubectl exec -n bookinfo deploy/fortio -c fortio -- \
  fortio load -c "$1" -qps 0 -n 30 -loglevel Warning http://httpbin:8000/get 2>&1 | grep -E "^Code"; }
# fortio's own circuit-breaker counters for httpbin
overflow_stats() { kubectl exec -n bookinfo deploy/fortio -c istio-proxy -- \
  pilot-agent request GET stats | grep 'httpbin.bookinfo' | grep -E 'pending_overflow|cx_overflow|pending_active'; }
```

## Example files

If you cloned the repository, the YAML is in [`../examples/`](../examples/). Apply it from
the `playground/` folder:

| File | What it shows |
| --- | --- |
| `examples/01-destinationrule-httpbin-connection-pool.yaml` | One connection, one waiting request, one request per connection. `load_test 3` trips it. |
| `examples/cases/c1-destinationrule-bigger-queue.yaml` | Same single connection, but 10 may wait. `load_test 3` gives no 503. |
| `examples/cases/c2-destinationrule-max-connections-only.yaml` | Only `maxConnections`. The queue stays near-unlimited, so the breaker never trips. |

## Things to try

- Run `load_test 1` and `load_test 3` against the `01-` file and compare the 200/503
  mix. One request at a time never trips a limit on requests at the same time.
- Apply `c1-` and find the number of parallel connections where 503s come back.
- Find the `UO` flag in `kubectl logs -n bookinfo deploy/fortio -c istio-proxy`, then
  confirm `httpbin`'s own sidecar log has no record of those requests.
- Run `overflow_stats` before and after a load test.
- Scale `httpbin-v1` to 3 replicas and confirm the *caller-side* pool limit does not move.
- Combine the `01-` limits with a VirtualService that retries on `5xx` and explain the
  counter jump.
- Ready for the exam-style drill? It covers both halves of circuit breaking, so it
  lives in the next module's playground:
  [Outlier Detection practice](../../../module-03/playground/docs/practice.md).

## Start over without a new cluster

```sh
kubectl delete destinationrule,virtualservice --all -n bookinfo
```

## When you're done

```sh
astrona destroy ats-014-playground-040-02
```

(`astrona destroy` takes the environment name, not the configuration path.)
