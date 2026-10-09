# Overview: Add External Workloads With WorkloadEntry (Playground)

> Declared in [`../config.yaml`](../config.yaml) under `metadata.docs.guide`.

This is a **playground**, not a lab: your training solar system, astronaut. It
starts a fresh cluster, installs Istio, the shuttle and two old freighters, and
then waits. There is no task, no `astrona submit` and no pass or fail. Explore,
break things, `astrona destroy`, start over.

## What's in the box

- A single-node `kind` Kubernetes cluster. `kubectl` is already pointed at it.
- **Istio 1.30.5**, installed with Helm (`istio-base` and `istiod` only, no
  gateways). `istiod` is mission control: it sends every proxy its orders.
  **DNS capture** is on, so a sidecar answers name lookups for hosts that only
  exist in a `ServiceEntry`, such as `freighter.starfleet.mesh`.
- Mesh-wide **access logs**, so every proxy writes one line per request. This
  is the ship's flight log, and you read it with
  `kubectl logs -n starfleet deploy/shuttle -c istio-proxy`.
- Namespace **`starfleet`** (the planet you work on), labelled `istio-injection=enabled`, with:
  - **`shuttle`**, your client pod with a sidecar (`2/2`). You send every test
    signal from it with `curl`.
  - **`freighter-vm-1`** and **`freighter-vm-2`**, two old freighters that stand
    in for virtual machines. Sidecar injection is switched off (`1/1`), there is
    no Service in front of them, and they answer HTTP on port `8080`. Their
    `/hostname` path answers with the pod's name. Their pod labels are
    `ship: freighter-vm-1` and `ship: freighter-vm-2`.
  - The **`freighter`** ServiceAccount both freighters run as.
- **No `WorkloadEntry`, `ServiceEntry`, `WorkloadGroup` or `DestinationRule`.**
  Writing them is the point of the module.

## Where the stand-in stops

A pod without a sidecar is not a real virtual machine. Naming, selecting and
routing work on it exactly as on a real machine. Three things do not:

- It cannot **prove** its identity: no sidecar holds a certificate for it.
- It cannot answer **mutual TLS**. With a `MESH_INTERNAL` `ServiceEntry`, callers
  start the handshake and fail with `503` and `WRONG_VERSION_NUMBER`. A
  `DestinationRule` with `tls` mode `DISABLE` for the host lets them use plain
  HTTP. A real onboarded machine does not need it.
- It cannot **register itself** against a `WorkloadGroup`, because it runs no
  `istio-agent`.

Its address also changes when the pod restarts. A real machine keeps its
address, so after a restart here, update the `address` in your `WorkloadEntry`.

## Helpers

Paste this once in each new terminal. It keeps the two freighter addresses in
variables, so you can read them with `echo $FREIGHTER_VM_1`:

```sh
FREIGHTER_VM_1=$(kubectl get pod -n starfleet -l ship=freighter-vm-1 -o jsonpath='{.items[0].status.podIP}')
FREIGHTER_VM_2=$(kubectl get pod -n starfleet -l ship=freighter-vm-2 -o jsonpath='{.items[0].status.podIP}')
```

## Things to try

Each idea below is a small change to the files you made while reading the
module. Edit your saved file, apply it with `kubectl apply -f`, and watch what
happens. The module's parts show the full YAML for every step.

- Before you write anything, signal a freighter by its address and read the
  flight log. It says `PassthroughCluster`: the shuttle's proxy does not know
  the freighter.
- Apply only the `WorkloadEntry`, and check
  `istioctl proxy-config cluster deploy/shuttle -n starfleet | grep freighter`.
  Still nothing: one object is not enough.
- Apply the `MESH_INTERNAL` `ServiceEntry` without the `DestinationRule`, and
  read the `WRONG_VERSION_NUMBER` in the flight log.
- Change one letter in the `workloadSelector` and watch the endpoint list empty
  out, with `503 UH` and a clean `istioctl analyze`.
- Leave `serviceAccount` out of an entry, and think about which policies could
  no longer name that machine.
- Point the `workloadSelector` at `ship: freighter-vm-1`. The selector picks the
  pod itself, without any `WorkloadEntry`.
- Write the `WorkloadGroup` and compare its `template` with your entries.

## Start over without a new cluster

```sh
kubectl delete workloadentry,workloadgroup,serviceentry,destinationrule --all -n starfleet
```

## Playground not working?

- `astrona list` shows running environments. "already exists" means an old
  one is still there: `astrona destroy ats-014-playground-070-03`, then run
  again.
- The full log path is printed at the end of `astrona run` (`~/.astrona/logs/`).
- `kubectl` talks to another cluster:
  `kubectl config use-context kind-astro-ats-014-playground-070-03`.
- The shuttle shows `1/1` instead of `2/2`: it has no sidecar. Run
  `kubectl rollout restart deploy/shuttle -n starfleet`.

## When you're done

```sh
astrona destroy ats-014-playground-070-03
```

(`astrona destroy` takes the environment name, not the configuration path.)
