# Overview: Mirror Live Traffic To A Shadow Service (Playground)

> Declared in [`../config.yaml`](../config.yaml) under `metadata.docs.guide`.

This is a **playground**, not a lab. The environment starts clean, runs
`bootstrap/prepare.sh`, applies the starting workloads, and then waits. There is
no task, no `astrona submit`, and no pass/fail. Explore, break things,
`astrona destroy`, start over.

## What's in the box

- A single-node `kind` Kubernetes cluster with `kubectl` already pointed at it.
- **Istio 1.30.5** (`demo` profile) and `istioctl` on your PATH.
- Namespace **`mirror-demo`**, injected, containing:
  - `notification-service-v1` (`["EMAIL"]`) and `notification-service-v2`
    (`["EMAIL","SMS"]`), one Service in front of both, and a `tester` client pod.
- **No Istio traffic configuration.** Nothing is routed and nothing is mirrored
  yet.

## Things to try

- Route 100% to `v1` with a full mirror to `v2`, then read
  `kubectl -n mirror-demo logs -l version=v2 -c istio-proxy` and find the
  copies in the shadow proxy's access log, which the caller never sees.
- Point `mirror.subset` at a subset no `DestinationRule` defines. The caller is
  completely unaffected — confirm for yourself that the only symptom is a silent
  shadow.
- Set `mirrorPercentage.value` to 10 and count shadow log lines over 100
  requests.
- Mirror to a different *host* rather than a subset of the same host.
- Add a header match so only requests carrying `testing: true` are shadowed, and
  check that unmatched requests produce no shadow log line at all.
- Compare the request count seen by `v1` and by `v2` at 100% mirroring and
  convince yourself the cluster really is carrying double the traffic.
- Look for `requestMirrorPolicies` in
  `istioctl proxy-config routes deploy/tester -n mirror-demo -o json`.

## When you're done

```sh
astrona destroy ats-014-playground-020-02
```

(`astrona destroy` takes the environment name, not the config path.)
