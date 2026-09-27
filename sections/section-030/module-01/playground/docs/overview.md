# Overview: Load Balancer Policy And Session Affinity (Playground)

> Declared in [`../config.yaml`](../config.yaml) under `metadata.docs.guide`.

This is a **playground**, not a lab. The environment starts clean, runs
`bootstrap/prepare.sh`, applies the starting workloads, and then waits. There is
no task, no `astrona submit`, and no pass/fail. Explore, break things,
`astrona destroy`, start over.

## What's in the box

- A single-node `kind` Kubernetes cluster with `kubectl` already pointed at it.
- **Istio 1.30.5** (`demo` profile) and `istioctl` on your PATH. The demo
  profile writes an Envoy access log to stdout, which is how you see which
  endpoint a proxy chose.
- Namespace **`lb-demo`**, injected, containing:
  - `httpbin` — **three replicas** behind a Service on port 8000. Three
    endpoints is the minimum that makes endpoint selection observable.
  - `tester` — a client pod with `curl`.
- **No `DestinationRule`**, so the mesh default load balancer is in force.

## Things to try

- Send 12 requests and read the chosen endpoint out of
  `kubectl -n lb-demo logs deploy/tester -c istio-proxy`. That log line, not the
  application response, is the proxy's own record of its decision.
- Set `consistentHash.httpHeaderName: x-user` and compare `alice`, `bob` and
  `carol`. Two names landing on the same pod is a hash collision, not a bug.
- Send requests with no `x-user` header at all under the same policy, and watch
  affinity silently disappear.
- Scale `httpbin` from 3 to 4 replicas during a stable-affinity run and count how
  many of your test values move. Roughly a quarter should.
- Try `useSourceIp: true` from two different client pods.
- Apply `simple` and `consistentHash` in the same `trafficPolicy` and read the
  rejection.
- Add a `canary` subset with its own `trafficPolicy` and confirm the subset value
  wins over the host value — and that the subset does *not* inherit the rest of
  the host policy.
- Compare `lbPolicy` in
  `istioctl proxy-config cluster deploy/tester -n lb-demo --fqdn httpbin.lb-demo.svc.cluster.local -o json`
  across each change.

## When you're done

```sh
astrona destroy ats-014-playground-030-01
```

(`astrona destroy` takes the environment name, not the config path.)
