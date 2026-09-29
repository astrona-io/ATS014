# Overview: How A Request Moves Through The Mesh (Playground)

> Declared in [`../config.yaml`](../config.yaml) under `metadata.docs.guide`.

This is a **playground**, not a lab. The environment starts clean, runs
`bootstrap/prepare.sh`, applies the starting workloads, and then waits. There is
no task, no `astrona submit`, and no pass/fail. Explore, break things,
`astrona destroy`, start over.

## What's in the box

- A single-node `kind` Kubernetes cluster. `kubectl` is already pointed at it.
- **Istio 1.30.5**, installed with the `demo` profile, plus `istioctl` on your
  PATH. Confirm with `istioctl version`.
- Namespace **`mesh-demo`**, labelled `istio-injection=enabled`, containing:
  - `api` — an nginx Deployment listening on `8080` that answers
    `{"service":"api","ok":true}`, behind a Service on port `80`.
  - `web` — a client pod with `curl` in it.
  - Both run **2/2**: the app container plus the injected `istio-proxy`.
- Namespace **`mesh-legacy`**, deliberately **not** injected, containing:
  - `legacy` — the same client image, running **1/1**, with no proxy.
- **No Istio traffic configuration at all.** This module is about the machinery
  that exists before you configure anything.

## Things to try

- Compare `kubectl -n mesh-demo get pods` with `kubectl -n mesh-legacy get pods`
  and list the containers in each pod. One number is the whole difference.
- Send a request from `web` and read both access logs — the caller's proxy and
  the receiver's proxy each logged the same request.
- Send the same request from `legacy` and notice there is no proxy log anywhere,
  because nothing intercepted it.
- Count what one proxy is configured with: `istioctl proxy-config cluster deploy/web -n mesh-demo | wc -l`.
- Run `istioctl proxy-status` and watch every proxy report `SYNCED`.
- Run `istioctl x describe pod <a web pod> -n mesh-demo` and read what it says
  about the pod before any Istio object exists.
- Delete the `api` Deployment and watch the endpoint list for its cluster empty
  out while the cluster itself stays.

## When you're done

```sh
astrona destroy ats-014-playground-000-01
```

(`astrona destroy` takes the environment name, not the config path.)
