# Overview: Timeouts And Retries (Playground)

> Declared in [`../config.yaml`](../config.yaml) under `metadata.docs.guide`.

Welcome aboard, astronaut. This is a **playground**, your training solar system, not a lab. The environment starts clean, installs
Istio and the apps, and then waits. There is no task, no `astrona submit`, and
no pass/fail. Explore, break things, `astrona destroy`, start over.

## What's in the box

- A single-node `kind` Kubernetes cluster (a small solar system of your own). `astrona run` points `kubectl` at it
  (context `kind-astro-ats-014-playground-040-01`).
- **Istio 1.30.5**, installed with Helm: `istio-base` and `istiod` only. There
  is no ingress or egress gateway, because this module does not need one.
- Access logs switched on for the whole mesh. Every sidecar writes one line
  per request, which is how you see timeouts and retries happen.
- Namespace **`bookinfo`**, labelled for sidecar injection, containing:
  - **Bookinfo**: `productpage`, `details`, `ratings` and `reviews` v1, v2 and
    v3, all on port 9080. Only v2 and v3 of `reviews` call `ratings`.
  - **`httpbin`** v1 and v2 behind one Service on port 8000. It fails on
    demand: `/status/503` always answers 503, `/status/200,503` picks one of
    the two at random, and `/delay/3` answers after 3 seconds.
  - **`curl`**, a client pod inside the mesh, for sending test requests.
  - A `DestinationRule`
    with the `reviews` subsets v1, v2 and v3.
  - A `VirtualService`
    that sends requests with the header `end-user: jason` to `reviews` v2 and
    everyone else to v1.
- The Bookinfo page at <http://127.0.0.1:9080/productpage>.
- **No timeout and no retry rule** yet. Only Istio's built-in default retry
  policy is active.

You need `kubectl` and `istioctl` 1.30.5 on your own machine. `astrona check`
tells you which tools are missing.

## Helper functions

Paste these into your terminal once per new terminal window. Every "Try it"
step in this module uses them.

```sh
status_and_time() { kubectl exec -n bookinfo deploy/curl -- curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" "$@"; }
count_received() { sleep 4; kubectl logs -n bookinfo -l app=httpbin -c istio-proxy --since=${2:-8s} | grep -c "$1"; }
```

`status_and_time` sends one request from the `curl` pod and prints the status
code and the total time. `count_received` counts how many requests the
`httpbin` pods really received, by reading their sidecar logs. That is the
only place where you can see retries, because the caller only ever gets one
answer.

## Things to try

The files are in [`../examples/`](../examples/). Apply them in number order.

- Time `/delay/3` with and without `04-timeouts/01-virtualservice-httpbin-timeout.yaml`,
  then read the `UT` flag in the `curl` pod's sidecar log.
- Make `ratings` slow with `04-timeouts/03-…` and give `reviews` a short limit
  with `04-timeouts/04-…`. Then read the `DI` line in the `reviews-v2` sidecar
  log and see that `reviews` still waited the full delay.
- Put the delay and the timeout on the same route
  (`04-timeouts/cases/c2-…`) and watch the timeout never fire.
- Send `/status/503` before and after `06-retries/01-…` and count the requests
  `httpbin` received: 1, then 4.
- Turn the timeout down until it cuts off the retries
  (`04-timeouts/cases/c3-…`), and check the arithmetic with
  `istioctl proxy-config routes deploy/curl -n bookinfo -o json`.
- Send a `POST` with retries on, then apply `06-retries/cases/c4-…` so only
  `GET` is retried.

When you want a real task, try the two exam-style drills in
[practice.md](practice.md).

## Start over without a new cluster

```sh
kubectl delete virtualservice httpbin ratings -n bookinfo
kubectl delete destinationrule ratings -n bookinfo
kubectl apply -f bootstrap/manifests/reviews-header-routing.yaml   # back to the jason → v2 route
```

Run these from the `playground/` folder.

## When you're done

```sh
astrona destroy ats-014-playground-040-01
```

(`astrona destroy` takes the environment name, not the configuration path.)
