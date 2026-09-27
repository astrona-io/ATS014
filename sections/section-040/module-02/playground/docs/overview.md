# Overview: Circuit Breaking With Connection Pool Limits (Playground)

> Declared in [`../config.yaml`](../config.yaml) under `metadata.docs.guide`.

This is a **playground**, not a lab. The environment starts clean, runs
`bootstrap/prepare.sh`, applies the starting workloads, and then waits. There is
no task, no `astrona submit`, and no pass/fail. Explore, break things,
`astrona destroy`, start over.

## What's in the box

- A single-node `kind` Kubernetes cluster with `kubectl` already pointed at it.
- **Istio 1.30.5** (`demo` profile) and `istioctl` on your PATH.
- Namespace **`circuit-demo`**, injected, containing:
  - `notification-service` — the backend, behind a Service on port 80.
  - `fortio` — a load generator. `curl` in a loop is sequential, and this whole
    module is about concurrency, so `fortio load -c <concurrency> -n <total>` is
    the tool. The pod has two containers, so commands need `-c fortio` or
    `-c istio-proxy`.
- **No `DestinationRule`**, so concurrency is unbounded.

## Things to try

- Run `fortio load -c 1` and `-c 3` against `maxConnections: 1` +
  `http1MaxPendingRequests: 1` and compare the 200/503 mix. Sequential load never
  trips a concurrency limit.
- Raise `http1MaxPendingRequests` to 10 and bisect for the concurrency level
  where 503s reappear.
- Find the `UO` flag in `kubectl logs deploy/fortio -c istio-proxy`, then confirm
  the backend's own log has no record of those requests at all.
- Read `upstream_rq_pending_overflow` and `upstream_cx_overflow` from
  `pilot-agent request GET stats` in the `istio-proxy` container.
- Set `maxRequestsPerConnection: 1` on its own and watch connection churn in
  `upstream_cx_total`.
- Combine a tight pool with `retryOn: 5xx` and a few attempts, then explain the
  request count you get. Retries amplify overload.
- Scale the backend up and confirm the *client-side* pool limit does not move.

## When you're done

```sh
astrona destroy ats-014-playground-040-02
```

(`astrona destroy` takes the environment name, not the config path.)
