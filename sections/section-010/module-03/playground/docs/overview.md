# Playground: Apply And Remove Traffic Rules Safely

This is a **playground**, not a lab. It starts a fresh cluster, installs Istio and the sample app, and then waits for you. There is no task, no `astrona submit`, and no pass or fail. Explore, break things, and start over whenever you like.

## What is in the playground

The playground is one small cluster with Istio and one namespace of workloads:

- A single-node `kind` Kubernetes cluster, with `kubectl` pointed at it.
- **Istio 1.30.5**, installed with Helm (`istio-base` and `istiod` only, no gateways). `istiod` is Istio's control plane: it sends configuration to every sidecar proxy. You need `istioctl` on your own machine.
- Envoy **access logs** for the whole mesh. An access log is the log where each sidecar proxy writes one line per request. Read the `shuttle` proxy's log with `kubectl logs -n starfleet deploy/shuttle -c istio-proxy`.
- The **`starfleet`** namespace, labelled `istio-injection=enabled`, so every pod has a sidecar proxy:
  - `bridge`, `cargo`, `scout` v1/v2/v3 and `navcom`: the Istio Bookinfo sample app with other names. `bridge` is the web frontend; the others are backends. The URL paths did not change, so `scout` answers on `http://scout:9080/reviews/0`.
  - `shuttle`: the test client. Send every test request from here.
  - `probe` v1/v2: an HTTP echo server on Service port `8000`. Paths such as `/delay/3` and `/status/503` make Istio's defaults easy to see.
- **No `DestinationRule` and no `VirtualService`.** You write and apply them yourself.
- The `bridge` page in your browser, at `http://127.0.0.1:9080/productpage`.

## Start over without a new cluster

Delete every `VirtualService` and `DestinationRule` in the namespace:

```sh
kubectl delete virtualservice,destinationrule --all -n starfleet
```

## When the playground does not work

- `astrona list` shows the running environments. "already exists" means an old one is still there: run `astrona destroy ats-014-playground-010-03`, then start it again.
- The full log path is printed at the end of `astrona run` (`~/.astrona/logs/`).
- If `kubectl` talks to another cluster, switch to this one: `kubectl config use-context kind-astro-ats-014-playground-010-03`.
- A pod that shows `1/1` instead of `2/2` has no sidecar proxy. Restart the workloads: `kubectl rollout restart deploy -n starfleet`.

## When you are done

Remove the playground:

```sh
astrona destroy ats-014-playground-010-03
```

`astrona destroy` takes the name of the playground, not the folder path.

## Practice tasks

Each task uses a `DestinationRule` named `scout` with the subsets `v1`, `v2` and `v3` (each selecting the pod label `version`), and a `VirtualService` named `scout` that sends every request to subset `v1`. Write both to files yourself and apply them with `kubectl apply -f`.

1. Apply the `VirtualService` **before** any `DestinationRule` exists, then send a request to `scout` straight away. Read the `503` and the `NC` flag in the `shuttle` proxy's access log, and the `IST0101` message from `istioctl analyze -n starfleet`. Then apply the `DestinationRule` and send the request again.
2. After each change, check that the `shuttle` proxy has the new subset with `istioctl proxy-config clusters deploy/shuttle -n starfleet` before you test.
3. Delete the `DestinationRule` while the `VirtualService` still uses it, and read the `503 NC` again. Then remove both objects in the safe order: the `VirtualService` first.
4. Apply a second `VirtualService` file with the same name, `scout`, that sends every request to `v3`. Check that `kubectl apply` prints `configured` and that `kubectl get virtualservice -n starfleet` still lists one object.
5. Check two defaults with no rules for `probe`: a request to `http://probe:8000/delay/3` waits the full 3 seconds, and a request to `http://probe:8000/status/503` reaches a `probe` pod only once.
