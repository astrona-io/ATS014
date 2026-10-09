# Overview: Control External Access With ServiceEntry (Playground)

> Declared in [`../config.yaml`](../config.yaml) under `metadata.docs.guide`.

This is a **playground**, not a lab: your training solar system, astronaut. It
starts a fresh cluster, installs Istio, the shuttle and the probe, and then waits. There is no task, no `astrona submit` and
no pass or fail. Explore, break things, `astrona destroy`, start over.

## What's in the box

- A single-node `kind` Kubernetes cluster. `kubectl` is already pointed at it.
- **Istio 1.30.5**, installed with Helm (`istio-base` and `istiod` only, no
  gateways). `istiod` is mission control: it sends every proxy its orders.
- The mesh at its **`ALLOW_ANY`** default. Switching to `REGISTRY_ONLY` is part
  of the module, not part of the setup.
- Mesh-wide **access logs**, so every proxy writes one line per signal. This
  is the ship's flight log, and you read it with
  `kubectl logs -n starfleet deploy/shuttle -c istio-proxy`.
- Namespace **`starfleet`** (the planet you work on), labelled `istio-injection=enabled`, with:
  - **`shuttle`**, your client pod inside the mesh. You send every test signal
    from it with the `curl` command.
  - **`probe`** v1 and v2 behind one Service on port `8000`, an echo service
    inside the cluster. Compare a call to it with a call that leaves the cluster.
- **No `ServiceEntry` and no `Sidecar`.** The star chart only knows your own
  solar system.

### Outbound internet

This playground calls `httpbin.org`, `de.wikipedia.org`, `en.wikipedia.org`
and `www.google.com`. Without outbound internet access you see network
failures, not mesh decisions. Run a plain `curl https://httpbin.org/get` on
your own machine first.

## Helper

Paste this once in each new terminal. It prints the status code, the time,
and the exit code of `curl`. `000` with exit code `35` or `56` means the
connection was cut.

```sh
call_external() { kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" --max-time 10 "$@"; echo "  exit=$?"; }
```

To see what the communications officer did with the last signal:

```sh
kubectl logs -n starfleet deploy/shuttle -c istio-proxy --tail=1
```

## Things to try

Each idea below uses the files you made while reading the module. The
module's parts show the full YAML for every step.

- Call `https://httpbin.org/get` before anything else and find
  `PassthroughCluster` in the flight log. Allowed, and invisible to Istio.
- Apply the `REGISTRY_ONLY` `Sidecar`. Call `httpbin.org` again (`000`,
  `BlackHoleCluster`), then `http://probe:8000/get` inside the cluster (`200`).
  Only the undeclared call broke.
- Chart `httpbin.org` on port `443` only. HTTPS works, `http://httpbin.org/get`
  does not.
- Add port `80` as `HTTP` and a `VirtualService` with `timeout: 2s`, then call
  `http://httpbin.org/delay/4`: `504` after 2 seconds. Then change the port's
  protocol to `TCP` and call it again: the timeout is gone.
- With port `80` charted, call `http://www.google.com/`: `502` from the
  `block_all` route.
- Move the `ServiceEntry` to the namespace `default`. The host stays blocked,
  because the `starfleet` `Sidecar` never takes in configuration from `default`.
- Run `istioctl proxy-config cluster deploy/shuttle -n starfleet | grep httpbin.org`
  before and after each `ServiceEntry` and watch the cluster appear.
- Try the exam-style task in [`practice.md`](practice.md).

## Start over without a new cluster

```sh
kubectl delete serviceentry,virtualservice,destinationrule --all -n starfleet
kubectl delete serviceentry --all -n default
kubectl delete sidecar default -n starfleet
```

## When you're done

```sh
astrona destroy ats-014-playground-070-01
```

(`astrona destroy` takes the environment name, not the configuration path.)
