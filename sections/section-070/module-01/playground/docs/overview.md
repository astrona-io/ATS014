# Overview: Control External Access With ServiceEntry (Playground)

> Declared in [`../config.yaml`](../config.yaml) under `metadata.docs.guide`.

This is a **playground**, not a lab. The environment starts clean, installs Istio and a few test apps, and then waits. There is no task, no `astrona submit`, and no pass/fail. Explore, break things, `astrona destroy`, start over.

Welcome aboard, astronaut. Think of your cluster as a solar system. Each pod is a spaceship, and its sidecar proxy is the communications officer that every signal goes through. Istio's service registry is the star chart. In this playground you decide which planets from other solar systems go on that chart.

## What's in the box

- A single-node `kind` Kubernetes cluster with `kubectl` already pointed at it (context `kind-astro-ats-014-playground-070-01`).
- **Istio 1.30.5**, installed with Helm: `istio-base` (the CRDs) and `istiod` (the control plane). No ingress or egress gateway.
- The mesh at its **`ALLOW_ANY`** default. Switching to `REGISTRY_ONLY` is part of the module, not part of the setup.
- Namespace **`bookinfo`**, labelled `istio-injection=enabled`, with:
  - `curl` — a client pod in the mesh. Send every request from here.
  - `httpbin` — a small test app inside the cluster, versions `v1` and `v2` behind one Service on port `8000`.
- Mesh-wide access logs (a `Telemetry` object in `istio-system`), so every sidecar writes one line per request.
- **No `ServiceEntry`, no `Sidecar`, no `VirtualService`.**
- [`../examples/`](../examples/) holds the module's YAML, numbered in the order you apply it, plus [`../examples/cases/`](../examples/cases/) for the break-it cases. Use them if you cloned the repository; the course parts write the same YAML to files for you.

### Outbound internet

This playground calls `httpbin.org`, `de.wikipedia.org`, `en.wikipedia.org` and `www.google.com`. Without outbound internet access you will see network errors rather than mesh decisions. Check a plain `curl` from your own machine first.

## Helper

Paste this once in each new terminal. It prints the status code, the time, and curl's exit code. `000` with exit `35` or `56` means the connection was cut.

```sh
call_external() { kubectl exec -n bookinfo deploy/curl -- curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" --max-time 10 "$@"; echo "  exit=$?"; }
```

To see what the communications officer did with the last request:

```sh
kubectl logs -n bookinfo deploy/curl -c istio-proxy --tail=1
```

## Things to try

- Call `https://httpbin.org/get` before anything else and find `PassthroughCluster` in the log. Allowed — and invisible to Istio.
- Apply [`01-sidecar-registry-only.yaml`](../examples/01-sidecar-registry-only.yaml). Call `httpbin.org` again (`000 exit=35`, `BlackHoleCluster`) and then `http://httpbin:8000/get` inside the cluster (`200`). Only the undeclared call broke.
- Apply [`02-serviceentry-httpbin-org-https.yaml`](../examples/02-serviceentry-httpbin-org-https.yaml). HTTPS now works; `http://httpbin.org/get` still does not, because only port `443` is on the chart.
- Apply [`03`](../examples/03-serviceentry-httpbin-org-http-and-https.yaml) and [`04`](../examples/04-virtualservice-httpbin-org-timeout.yaml), then call `http://httpbin.org/delay/4`. A `504` after two seconds: an Istio timeout on somebody else's API.
- Case 1: apply [`cases/c1-serviceentry-in-other-namespace.yaml`](../examples/cases/c1-serviceentry-in-other-namespace.yaml) (after `kubectl delete se --all -n bookinfo`). The host stays blocked, because the `bookinfo` `Sidecar` never takes in configuration from `default`.
- Case 2: apply [`cases/c2-serviceentry-wildcard.yaml`](../examples/cases/c2-serviceentry-wildcard.yaml) and call `https://de.wikipedia.org/`. One wildcard entry, a whole domain — with `resolution: NONE`, because DNS cannot look up `*.wikipedia.org`.
- Run `istioctl proxy-config cluster deploy/curl -n bookinfo | grep httpbin.org` before and after each `ServiceEntry` and watch the cluster appear.
- Try the exam-style drill in [`practice.md`](practice.md).

## Start over without a new cluster

```sh
kubectl delete vs,se --all -n bookinfo
kubectl delete sidecar default -n bookinfo
```

## When you're done

```sh
astrona destroy ats-014-playground-070-01
```

(`astrona destroy` takes the environment name, not the configuration path.)
