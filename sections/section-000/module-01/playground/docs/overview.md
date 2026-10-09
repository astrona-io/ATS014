# Overview: How A Request Moves Through The Mesh (Playground)

This is a **playground**, not a lab. It starts clean, installs Istio and the sample app, and then waits for you. There is no task, no `astrona submit`, and no pass or fail. Explore, break things, and start over whenever you like.

## What is in the playground

The playground is one small cluster with Istio and two namespaces that differ in one setting:

- A single-node `kind` Kubernetes cluster, with `kubectl` pointed at it.
- **Istio 1.30.5** (`istio-base` and `istiod`, installed with Helm), with Envoy access logs switched on for the whole mesh. An access log is the log where each sidecar proxy writes one line per request. You need `istioctl` on your own machine.
- The **`starfleet`** namespace, with sidecar injection switched on. Every pod shows `2/2`: the application container plus the `istio-proxy` sidecar proxy.
  - `bridge`, `cargo`, `scout` v1/v2/v3 and `navcom`: the Bookinfo sample app with other names. `bridge` is the web frontend; the others are backends.
  - `shuttle`: the test client. Send every test request from here.
  - `probe` v1/v2: an HTTP echo server. Its Service listens on port `8000`, and its pods on `8080`.
- The **`outpost`** namespace, with sidecar injection switched **off** on purpose. Its one pod, `drifter`, shows `1/1`: it runs the same client image as `shuttle`, with no sidecar proxy.
- The `bridge` page at `http://127.0.0.1:9080/productpage`.
- **No Istio traffic configuration at all.** This playground shows what exists before you configure anything.

## When you are done

Remove the playground:

```sh
astrona destroy ats-014-playground-000-01
```

`astrona destroy` takes the name of the playground, not the folder path.

## Practice tasks

Each task can be done with the commands below and needs no Istio objects:

- Compare `kubectl -n starfleet get pods` with `kubectl -n outpost get pods`. One number in the `READY` column is the whole difference.
- Send a request from `shuttle` to `cargo` and read both access logs with `kubectl logs <pod> -c istio-proxy`. The client's line says `outbound`, the server's line says `inbound`.
- Send the same request from `drifter`, and check that only the `cargo` proxy logs it.
- Run `istioctl proxy-status` and look for `drifter`. It is not there, because it has no proxy.
- Follow a request to `probe` through all four layers with `istioctl proxy-config listener`, `routes`, `cluster` and `endpoints`. Notice the port change from `8000` to `8080`.
- Count how many clusters one proxy holds: `istioctl proxy-config cluster deploy/shuttle -n starfleet | wc -l`.
- Scale `cargo-v1` to zero replicas and read the `503 UH` in the `shuttle` access log. Then scale it back to one.
