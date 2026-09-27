# Overview: TLS Origination At The Egress Gateway (Playground)

> Declared in [`../config.yaml`](../config.yaml) under `metadata.docs.guide`.

This is a **playground**, not a lab. The environment starts clean, runs
`bootstrap/prepare.sh`, applies the starting workloads, and then waits. There is
no task, no `astrona submit`, and no pass/fail. Explore, break things,
`astrona destroy`, start over.

## What's in the box

- A single-node `kind` Kubernetes cluster with `kubectl` already pointed at it.
- **Istio 1.30.5** (`demo` profile), including `istio-egressgateway` in
  `istio-system`, plus `istioctl` on your PATH.
- Namespace **`egwtls-demo`**, injected, with a `tester` client pod.
- The mesh at its `ALLOW_ANY` default.
- **No Istio configuration at all** — the five objects are yours to write.

### Outbound internet

The commands reach `httpbin.org`. Without outbound internet access you will see
network errors rather than mesh behaviour.

## Things to try

- Move the origination `DestinationRule` from `httpbin.org` to
  `istio-egressgateway.istio-system.svc.cluster.local` and confirm nothing
  originates. Traffic policy is applied by the proxy that *calls* the host.
- Route the gateway-side rule to port 80 of the external host instead of 443 and
  read the failure.
- Declare only port 80 in the `ServiceEntry` and see stage 2 lose its
  destination.
- Run the `transportSocket` count on both proxies:

  ```sh
  istioctl proxy-config cluster deploy/istio-egressgateway -n istio-system --fqdn httpbin.org -o json | grep -c transportSocket
  istioctl proxy-config cluster deploy/tester -n egwtls-demo --fqdn httpbin.org -o json | grep -c transportSocket
  ```

  One and zero. That pair settles where origination happens.
- Remove `sni` and see whether this particular endpoint still completes the
  handshake.
- Build the section 070 sidecar-side version in the same namespace and compare
  the two configurations object by object. Only one object differs in placement.
- Switch to `tls.mode: MUTUAL` with a `credentialName` pointing at a secret that
  does not exist, and note that the failure is silent — no listener, no message
  naming the cause.
- Add an `AuthorizationPolicy` on the egress gateway allowing only one service
  account to use it.

## When you're done

```sh
astrona destroy ats-014-playground-080-02
```

(`astrona destroy` takes the environment name, not the config path.)
