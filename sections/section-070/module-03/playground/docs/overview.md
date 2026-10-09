# Overview: Add External Workloads With WorkloadEntry (Playground)

This is a **playground**, not a lab. It starts a fresh cluster, installs Istio, a test client and two pods that stand in for virtual machines, and then waits for you. There is no task, no `astrona submit`, and no pass or fail. Explore, break things, and start over whenever you like.

## What is in the playground

The playground is one small cluster with Istio and one namespace:

- A single-node `kind` Kubernetes cluster, with `kubectl` pointed at it.
- **Istio 1.30.5** (`istio-base` and `istiod`, installed with Helm, no gateways). `istiod` is Istio's control plane: it builds the configuration for every sidecar proxy and sends it to them. DNS proxying is on, so the sidecar proxy answers DNS lookups for hosts that exist only in a `ServiceEntry`, such as `freighter.starfleet.mesh`.
- Mesh-wide **access logs**: every sidecar proxy writes one line per request. Read them with `kubectl logs -n starfleet deploy/shuttle -c istio-proxy`.
- The **`starfleet`** namespace, labelled `istio-injection=enabled`, with:
  - `shuttle`: the test client, with a sidecar proxy (`2/2`). Send every test request from here with `curl`.
  - `freighter-vm-1` and `freighter-vm-2`: two pods that stand in for virtual machines. Sidecar injection is off (`1/1`), there is no Service in front of them, and they answer HTTP on port `8080`. The `/hostname` path returns the pod name. Their pod labels are `ship: freighter-vm-1` and `ship: freighter-vm-2`.
  - The `freighter` ServiceAccount that both freighter pods run as.
- **No `WorkloadEntry`, `ServiceEntry`, `WorkloadGroup` or `DestinationRule`.** You write them yourself.

## Where the stand-in differs from a real virtual machine

A pod without a sidecar proxy is not a real virtual machine. Host names, selectors and routing work on it exactly as on a real machine. Three things do not:

- It cannot prove its identity, because no sidecar proxy holds a certificate for it.
- It cannot accept mTLS (mutual TLS). With a `MESH_INTERNAL` `ServiceEntry`, the caller's proxy uses mTLS and the request fails with `503` and `WRONG_VERSION_NUMBER` in the access log. A `DestinationRule` with `tls` mode `DISABLE` for the host lets callers send plain HTTP. A real machine that runs `istio-agent` does not need it.
- It cannot register itself against a `WorkloadGroup`, because it does not run `istio-agent`, the Istio program that starts the sidecar proxy on a real machine.

The address of a stand-in pod also changes when the pod restarts. A real machine keeps its address, so after a restart here, update the `address` in your `WorkloadEntry`.

## Helpers

Paste this once in each new terminal. It keeps the two freighter addresses in variables, so you can read them with `echo $FREIGHTER_VM_1` and `echo $FREIGHTER_VM_2`:

```sh
FREIGHTER_VM_1=$(kubectl get pod -n starfleet -l ship=freighter-vm-1 -o jsonpath='{.items[0].status.podIP}')
FREIGHTER_VM_2=$(kubectl get pod -n starfleet -l ship=freighter-vm-2 -o jsonpath='{.items[0].status.podIP}')
```

To remove every Istio object you created and start over without a new cluster:

```sh
kubectl delete workloadentry,workloadgroup,serviceentry,destinationrule --all -n starfleet
```

## If the playground does not work

- `astrona list` shows the running environments. If `astrona run` says "already exists", an old one is still there: run `astrona destroy ats-014-playground-070-03`, then run it again.
- The full log path is printed at the end of `astrona run` (`~/.astrona/logs/`).
- If `kubectl` talks to another cluster, run `kubectl config use-context kind-astro-ats-014-playground-070-03`.
- If `shuttle` shows `1/1` instead of `2/2`, it has no sidecar proxy. Run `kubectl rollout restart deploy/shuttle -n starfleet`.

## When you are done

Remove the playground:

```sh
astrona destroy ats-014-playground-070-03
```

`astrona destroy` takes the name of the playground, not the folder path.

## Practice tasks

Each task is a small change to the files you write while you read the module. Edit your saved file, apply it with `kubectl apply -f`, and watch what happens:

- Before you write anything, send a request to a freighter pod by its IP address and read the `shuttle` access log. It says `PassthroughCluster`: the proxy does not know the freighter.
- Apply only a `WorkloadEntry`, and run `istioctl proxy-config cluster deploy/shuttle -n starfleet | grep freighter`. It prints nothing: an entry alone gives no cluster.
- Apply a `MESH_INTERNAL` `ServiceEntry` without the `DestinationRule`, and find `WRONG_VERSION_NUMBER` in the access log.
- Change one letter in the `workloadSelector`, and watch the endpoint list become empty, with `503 UH` and a clean `istioctl analyze`.
- Leave `serviceAccount` out of an entry, and work out which policies could no longer name that machine.
- Point the `workloadSelector` at `ship: freighter-vm-1`. The selector then picks the pod itself, without any `WorkloadEntry`.
- Write a `WorkloadGroup`, and compare its `template` with your entries.
