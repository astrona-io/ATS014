# Overview: Timeouts And Retries (Playground)

> Declared in [`../config.yaml`](../config.yaml) under `metadata.docs.guide`.

This is a **playground**, not a lab. The environment starts clean, runs
`bootstrap/prepare.sh`, applies the starting workloads, and then waits. There is
no task, no `astrona submit`, and no pass/fail. Explore, break things,
`astrona destroy`, start over.

## What's in the box

- A single-node `kind` Kubernetes cluster with `kubectl` already pointed at it.
- **Istio 1.30.5** (`demo` profile) and `istioctl` on your PATH.
- Namespace **`resilience-demo`**, injected, containing:
  - `httpbin` on port 8000 with two endpoints that make failure controllable:
    `/delay/<seconds>` sleeps before answering, `/status/<code>` returns that
    status immediately.
  - `tester` — a client pod with `curl`.
- **No `VirtualService`**, so there is no route timeout and only Istio's implicit
  default retry policy is in effect.

## Things to try

- Time `/delay/10` with and without a `timeout: 5s` route, using
  `curl -w '%{http_code} %{time_total}s\n'`.
- Set `attempts: 3`, `perTryTimeout: 1s`, `timeout: 5s`, call `/status/503`, and
  count `/status/503` lines in `kubectl logs deploy/httpbin -c istio-proxy`. Four
  is correct for one client request.
- Drop `timeout` to `2s` with the same retry policy and find the `UT` flag in the
  caller's access log. That is the budget trap.
- Set `attempts: 0`, call `/status/503`, and confirm exactly one request reaches
  the server — proof that the implicit default was doing something.
- Use `retryOn: retriable-status-codes` with `retriableStatusCodes: [418]` and
  test against `/status/418`.
- Check that `retryOn: 5xx` does nothing for `/status/400`.
- Add `retryRemoteLocalities: true` and reason about when it would help.
- Compare `"timeout"`, `numRetries` and `perTryTimeout` in
  `istioctl proxy-config routes deploy/tester -n resilience-demo -o json` after
  each change.

## When you're done

```sh
astrona destroy ats-014-playground-040-01
```

(`astrona destroy` takes the environment name, not the config path.)
