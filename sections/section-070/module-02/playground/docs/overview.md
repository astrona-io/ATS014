# Overview: TLS Origination For External Services (Playground)

> Declared in [`../config.yaml`](../config.yaml) under `metadata.docs.guide`.

Welcome aboard, astronaut. This is a **playground**, not a lab. The environment starts clean, runs
`bootstrap/prepare.sh`, applies the starting workloads, and then waits. There is
no task, no `astrona submit`, and no pass/fail. Explore, break things,
`astrona destroy`, start over.

## What's in the box

- A single-node `kind` Kubernetes cluster with `kubectl` already pointed at it.
- **Istio 1.30.5** (`demo` profile) and `istioctl` on your PATH. The mesh is at
  its `ALLOW_ANY` default, so external calls are not blocked — this module is
  about visibility (can the communications officer read the signal?), not permission.
- Namespace **`tlsorig-demo`**, injected, with a `tester` client pod.
- **No Istio configuration at all.**

### Outbound internet

The commands reach `httpbin.org`. Without outbound internet access you will see
network errors rather than mesh behaviour.

## Things to try

- Call `https://httpbin.org/get` directly and read
  `kubectl logs deploy/tester -c istio-proxy`. The `"- - -"` where the method and
  path should be is the problem this module solves.
- Build the three objects one at a time and note the distinct failure each
  omission produces: no port 80 in the `ServiceEntry`, no `VirtualService`
  redirect, no `DestinationRule`.
- Put `tls.mode: SIMPLE` at the top of `trafficPolicy` instead of under
  `portLevelSettings` and watch the plaintext side break.
- Remove `sni` and see whether the handshake still succeeds for this particular
  host. Some endpoints tolerate it; shared-hosting ones do not.
- Confirm origination from the destination's own view:
  `curl -s http://httpbin.org/headers | grep -i X-Forwarded-Proto`.
- Keep calling `https://` from the application with everything configured, and
  confirm origination never happens — the app must speak `http://`.
- Add a `timeout` or a retry policy on the now-visible HTTP route and watch
  layer-7 features work against an external service.
- Look for `transportSocket` in
  `istioctl proxy-config cluster deploy/tester -n tlsorig-demo --fqdn httpbin.org -o json`.

## When you're done

```sh
astrona destroy ats-014-playground-070-02
```

(`astrona destroy` takes the environment name, not the configuration path.)
