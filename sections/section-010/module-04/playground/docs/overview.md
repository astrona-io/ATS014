# Playground: Compose And Scope VirtualServices With delegate And exportTo

This is a **playground**, not a lab. It starts a fresh cluster, installs Istio and the sample workloads, and then waits for you. There is no task, no `astrona submit`, and no pass or fail. Explore, break things, and start over whenever you like.

## What is in the playground

The playground is one small cluster with Istio and two namespaces of workloads:

- A single-node `kind` Kubernetes cluster, with `kubectl` pointed at it.
- **Istio 1.30.5**, installed with Helm (`istio-base` and `istiod` only, no gateways). `istiod` is Istio's control plane: it sends configuration to every sidecar proxy. You need `istioctl` on your own machine.
- Envoy **access logs** for the whole mesh. An access log is the log where each sidecar proxy writes one line per request. Read the `shuttle` proxy's log with `kubectl logs -n starfleet deploy/shuttle -c istio-proxy`.
- The **`starfleet`** namespace, labelled `istio-injection=enabled`, so every pod has a sidecar proxy:
  - `probe` v1 and v2: an HTTP echo server. The Service `probe` has two ports, `8000` and `8001`, and both reach the same pods. The path `/hostname` returns the pod name, `/delay/3` waits 3 seconds, and `/get` echoes the request.
  - `shuttle` and `patrol`: two client pods with `curl`. They differ only in the label `app` and the service account.
- The **`dock`** namespace, also with sidecar injection, with one more `shuttle` client. A client in `dock` must call `probe.starfleet.svc.cluster.local`, because a short host name resolves in the client's own namespace.
- A `DestinationRule` named `probe` with the subsets `v1` and `v2` (selecting the pod label `version`).
- **No `VirtualService`.** You write and apply them yourself.

## The helper

`count-versions.sh` sends 10 requests from a client pod and counts which probe version answered. Run it with `astrona res run`. The first argument is the client's namespace, the second is the client's Deployment, and the rest goes to `curl`:

```sh
astrona res run count-versions.sh -- starfleet shuttle http://probe:8000/hostname
```

The `examples/` folder holds the YAML files used in the reading pages. Apply them with `kubectl apply -f`.

## Start over without a new cluster

Delete every `VirtualService` in both namespaces. Then apply the original `DestinationRule` again:

```sh
kubectl delete virtualservice --all -n starfleet
kubectl delete virtualservice --all -n dock
kubectl apply -f bootstrap/manifests/destinationrule-probe.yaml
```

## When the playground does not work

- `astrona list` shows the running environments. "already exists" means an old one is still there: run `astrona destroy ats-014-playground-010-04`, then start it again.
- The full log path is printed at the end of `astrona run` (`~/.astrona/logs/`).
- If `kubectl` talks to another cluster, switch to this one: `kubectl config use-context kind-astro-ats-014-playground-010-04`.
- A pod that shows `1/1` instead of `2/2` has no sidecar proxy. Restart the workloads: `kubectl rollout restart deploy -n starfleet` and `kubectl rollout restart deploy -n dock`.

## When you are done

Remove the playground:

```sh
astrona destroy ats-014-playground-010-04
```

`astrona destroy` takes the name of the playground, not the folder path.

## Practice tasks

1. Write a delegate `VirtualService` with no `hosts` that sends every path to subset `v2`, and a root `VirtualService` for `probe` that delegates the prefix `/hostname` to it. Check with `count-versions.sh` that `/hostname` answers from `probe-v2` and that `/get` gets a `404`.
2. Add a `fault` abort of `503` to a `VirtualService` for `probe` with `exportTo: ["."]`. Send a request from `starfleet` and from `dock`, and compare. Then change the list to `[".", "dock"]`.
3. Apply a `DestinationRule` for `probe` with `exportTo: ["."]` and keep a `VirtualService` that is visible in `dock`. Read the `503` and the `NC` flag in the `dock` proxy's access log, then fix it.
4. Compare `istioctl proxy-config routes deploy/shuttle -n starfleet --name 8000` with the same command for `deploy/patrol`, after you apply a `VirtualService` with a `sourceLabels` rule for `app: patrol`.
5. Add a `port: 8001` match to a `VirtualService` and send the same request to port `8000` and port `8001`. Check which version answers each.
