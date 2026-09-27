# Overview: Fault Injection With Delays And Aborts (Playground)

> Declared in [`../config.yaml`](../config.yaml) under `metadata.docs.guide`.

This is a **playground**, not a lab. The environment starts clean, runs
`bootstrap/prepare.sh`, applies the starting workloads, and then waits. There is
no task, no `astrona submit`, and no pass/fail. Explore, break things,
`astrona destroy`, start over.

## What's in the box

- A single-node `kind` Kubernetes cluster with `kubectl` already pointed at it.
- **Istio 1.30.5** (`demo` profile) and `istioctl` on your PATH.
- Namespace **`fault-demo`**, injected, containing a two-hop call chain:

  ```text
  throwaway curl pod  →  booking-service  →  notification-service
  ```

  `booking-service` (port 80) calls `notification-service` on every `/book`
  request, so you can watch a *service* react to a failing dependency rather
  than just watching curl react.
- There is no permanent client pod. Use
  `kubectl -n fault-demo run t0 --rm -i --restart=Never --image=curlimages/curl -- ...`;
  the namespace is injected, so the throwaway pod gets a sidecar too.
- **No `VirtualService`.**

## Things to try

- Inject `delay.fixedDelay: 2s` on `notification-service` and time the end-to-end
  `/book` call. Then move the same fault onto `booking-service` and work out why
  the result is different.
- Combine `delay.fixedDelay: 7s` with `timeout: 3s` on the same route and watch
  the 504 arrive in about three seconds, on demand.
- Inject `abort.httpStatus: 503` plus a retry policy, then read
  `kubectl logs deploy/booking-service-v1 -c istio-proxy` and count the attempts.
  Every attempt is aborted, so retries do not help — that is the lesson.
- After an abort run, check `kubectl logs deploy/notification-service-v1` and
  confirm the destination has no record of the aborted requests at all.
- Set `delay.percentage.value: 10` and measure the latency distribution over 100
  requests.
- Scope a 100% abort behind `match` on `end-user: tester` and confirm unheaded
  requests are untouched. Then remove the header propagation assumption by
  scoping on something `booking-service` does not forward, and see it fail.
- Leave an unscoped abort in place, walk away, and come back — it is still there.
  That is the production hazard.

## When you're done

```sh
astrona destroy ats-014-playground-050-01
```

(`astrona destroy` takes the environment name, not the config path.)
