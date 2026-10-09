# Overview: Circuit Breaking With Connection Pool Limits (Playground)

This is a **playground**, not a graded lab. The cluster starts, installs Istio, deploys the workloads below, and then waits. There is no task, no `astrona submit` and no pass or fail. Explore, break things, run `astrona destroy`, and start over.

## What is in your playground

- A single-node `kind` cluster. `astrona run` points `kubectl` at it (context `kind-astro-ats-014-playground-040-02`).
- **Istio 1.30.5**, installed with Helm: `istio-base` (the Istio resource types) and `istiod` (the control plane, which sends configuration to every sidecar proxy). There is no ingress or egress gateway.
- Access logs switched on for the whole mesh, so every sidecar proxy writes one line per request.
- The namespace **`starfleet`**, with sidecar injection switched on. It contains:
  - `probe-v1` and `probe-v2`: an HTTP echo server, both behind one Service `probe` on port `8000`. `/get` answers `200`, and `/status/503` always answers `503`.
  - `shuttle`: a test client pod that sends single requests with `curl`.
  - `fortio`: a load generator that sends many requests at the same time. Its pod has the `sidecar.istio.io/statsInclusionPrefixes: "cluster.outbound"` annotation, so its sidecar proxy keeps the overflow counters.
- Every pod shows `2/2`: the application plus its `istio-proxy` sidecar container.
- **No `DestinationRule`**, so there are no connection pool limits yet.

## Helpers

Paste these once per terminal:

```sh
# 30 requests to the probe over N connections at the same time, from fortio; prints the status-code summary
load_test() { kubectl exec -n starfleet deploy/fortio -c fortio -- \
  fortio load -c "$1" -qps 0 -n 30 -loglevel Warning http://probe:8000/get 2>&1 | grep -E "^Code"; }
# fortio's own overflow counters for the probe
overflow_stats() { kubectl exec -n starfleet deploy/fortio -c istio-proxy -- \
  pilot-agent request GET stats 2>/dev/null | grep 'probe.starfleet' | grep -E 'pending_overflow|cx_overflow|pending_active'; }
```

## Set connection pool limits

A `DestinationRule` with a `trafficPolicy.connectionPool` caps how much work each client proxy may have open to the `probe` Service at the same time. Save this as `destinationrule-probe-connection-pool.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: probe
  namespace: starfleet
spec:
  host: probe
  trafficPolicy:
    connectionPool:
      tcp:
        maxConnections: 1
      http:
        http1MaxPendingRequests: 1
        maxRequestsPerConnection: 1
```

Apply it:

```sh
kubectl apply -f destinationrule-probe-connection-pool.yaml
```

## Start over without a new cluster

```sh
kubectl delete destinationrule,virtualservice --all -n starfleet
```

## When you are done

```sh
astrona destroy ats-014-playground-040-02
```

`astrona destroy` takes the environment name, not the configuration path.

## Practice tasks

- Run `load_test 1` and `load_test 3`, and compare the mix of `200` and `503`. Requests sent one at a time never trip a limit on requests at the same time.
- Raise `http1MaxPendingRequests` to `10` and find how many parallel connections bring the `503`s back.
- Remove `http1MaxPendingRequests` and keep only `maxConnections`. Do the `503`s stop?
- Find the `UO` flag in `kubectl logs -n starfleet deploy/fortio -c istio-proxy`, then look for `inbound` lines with `UO` in the access logs of the `probe` pods' proxies.
- Run `overflow_stats` before and after a load test.
- Read the limits on both ends with `istioctl proxy-config cluster`, once for `deploy/fortio` and once for a `probe` pod with `--direction inbound`.
- Add a `VirtualService` that retries on `5xx`, send requests to `/status/503`, and count the retries in the `upstream_rq_retry` counter.
