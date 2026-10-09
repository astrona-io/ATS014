# Overview: Scope Proxy Configuration With The Sidecar Resource (Playground)

This is a playground, not a graded lab. It starts clean, installs Istio and two namespaces with workloads, and then waits for you. There is no task, no `astrona submit` and no pass or fail. Try things, break them, destroy the playground and start again.

## What is in the playground

The playground is a single-node `kind` Kubernetes cluster, and `astrona run` points `kubectl` at it. It runs **Istio 1.30.5** (`istio-base` and `istiod`), installed with Helm. You need `istioctl` on your own machine.

Every sidecar proxy writes an access log: one line per request or connection, which you read with `kubectl logs <pod> -c istio-proxy`. Two namespaces have sidecar injection switched on:

| Namespace | Workload | What it does |
| --- | --- | --- |
| `starfleet` | `shuttle` | Test client pod; send every test request from here |
| `starfleet` | `cargo` | Backend Service on port `9080` (`/details/0`) |
| `outpost` | `probe` v1, v2 | HTTP echo server on Service port `8000` (`/get`, `/headers`) |

There is **no** `Sidecar` resource. The `Sidecar` resource is the Istio object that limits which hosts `istiod` sends to the proxies in a namespace. Without one, every proxy holds every Service, and the mesh uses Istio's default outbound policy, `ALLOW_ANY`.

## Start over

Remove every `Sidecar` you created:

```sh
kubectl delete sidecar --all -n starfleet
kubectl delete sidecar --all -n outpost
kubectl delete sidecar --all -n istio-system
```

## When you are done

```sh
astrona destroy ats-014-playground-010-02
```

`astrona destroy` takes the name of the environment, not the path of its configuration.

## Practice tasks

Write each `Sidecar` to a file, apply it with `kubectl apply -f`, and check the result with `istioctl proxy-config` before you send any request.

1. Count the `shuttle` proxy's clusters with `istioctl proxy-config cluster deploy/shuttle -n starfleet | wc -l`. Count them again after each `Sidecar` you apply.
2. Apply a namespace-wide `Sidecar` in `starfleet` with only `./*` and `istio-system/*`. Check that `probe.outpost` is gone from the `shuttle` proxy's cluster list. Then call `http://probe.outpost:8000/get` anyway, and find `PassthroughCluster` in the access log.
3. Add `outboundTrafficPolicy` with `mode: REGISTRY_ONLY` to the same `Sidecar`, and call `probe` again. Expect `000` from `curl`, and `BlackHoleCluster` in the access log.
4. Add a selector `Sidecar` for `app: shuttle` that lists only `./*`. Compare the `shuttle` proxy's cluster list with the `cargo-v1` proxy's list.
5. Leave out `istio-system/*` and see which clusters the `shuttle` proxy loses.
6. Put a `Sidecar` without a selector in `istio-system`, and watch the `probe-v1` proxy's cluster list in `outpost` get smaller.
