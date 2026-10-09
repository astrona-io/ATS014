# Add External Workloads With WorkloadEntry

Some workloads never run in Kubernetes: a database on a virtual machine, an old service nobody has moved into a container, a device with a fixed IP address. Pods in the mesh can often reach such a machine by its address, but Istio knows nothing about it. This module adds such machines to the mesh with three Istio objects.

A **`WorkloadEntry`** describes one machine outside Kubernetes: its address, its labels and the ServiceAccount it runs as. A **`ServiceEntry`** with `location: MESH_INTERNAL` and a `workloadSelector` gives a group of those machines one host name and port. A **`WorkloadGroup`** is a template that real virtual machines register against, so `istiod` writes their entries for them.

## Learning objectives

After this module you can:

- Describe a machine outside Kubernetes with a `WorkloadEntry`: its address, labels and service account.
- Explain the identity a `serviceAccount` gives that machine, and why policies need it.
- Group entries into one host with a `MESH_INTERNAL` `ServiceEntry` and a `workloadSelector`.
- State what `MESH_INTERNAL` changes compared with `MESH_EXTERNAL`, and recognise the failed mTLS (mutual TLS) handshake it causes when the machine has no sidecar proxy.
- Find a `workloadSelector` that matches no entry from a `503 UH` and the proxy's endpoint list.
- Say what a `WorkloadGroup` is for, and what a real virtual machine needs before it can register itself.

## Before you start

The module expects some knowledge of Istio and Kubernetes, and a playground that is ready before the first hands-on step.

### What you should already know

- **How the mesh works.** A sidecar proxy (Envoy) runs next to every pod in the mesh, and `istiod`, Istio's control plane, sends it its configuration. You read that configuration with `istioctl proxy-config`.
- **What a `ServiceEntry` is.** It adds a host that Kubernetes does not know to Istio's service registry, with the fields `hosts`, `ports`, `location` and `resolution`.
- **Kubernetes basics.** Namespaces, Deployments, ServiceAccounts, pod labels and `kubectl exec`.

### What is in your playground

Your playground is one `kind` cluster with **Istio 1.30.5** installed with Helm. Istio's DNS proxying is switched on: the sidecar proxy answers DNS lookups for hosts in the service registry, so a host that exists only in a `ServiceEntry` can still be called by name. Access logs are on, so each sidecar proxy writes one line per request. Everything is in the `starfleet` namespace:

| Workload | What it is |
| --- | --- |
| `shuttle` | Test client pod with a sidecar proxy (`2/2`). You send every test request from here with `curl` |
| `freighter-vm-1`, `freighter-vm-2` | Two pods that stand in for virtual machines. Sidecar injection is off (`1/1`), there is no Service in front of them, and they answer HTTP on port `8080`. The `/hostname` path returns the pod name, so you can see which one answered |
| `freighter` ServiceAccount | The ServiceAccount both freighter pods run as |

The freighter pods carry the labels `ship: freighter-vm-1` and `ship: freighter-vm-2`. The label you give them in the mesh, `app: freighter`, is different on purpose, so you always know which object did the selecting. No `WorkloadEntry`, `ServiceEntry`, `WorkloadGroup` or `DestinationRule` exists yet.

### Where the stand-in differs from a real virtual machine

A pod without a sidecar is not a real virtual machine. It lives on the pod network, and its address changes when the pod restarts. It does not run `istio-agent`, the Istio program that starts the sidecar proxy on a real machine and gets its certificate. What it shows well is the subject of this module: an address that answers, which the mesh knows nothing about.

So three things only work on a real machine, and the parts say so when they come up. The stand-in cannot prove its identity, because no sidecar holds a certificate for it. It cannot accept mTLS, so you turn mTLS off for its host with a `DestinationRule`, only because it is a stand-in. And it cannot register itself against a `WorkloadGroup`.

Start your playground now, and keep it running while you read the parts:

<!-- astrona:playground -->

## The order of the parts

The module has four parts, a lab after the third part, a lab after the fourth part, and a summary at the end.

The first part reaches a machine by its address, shows that the mesh does not know it, and describes it with a first `WorkloadEntry`. The second part gives the machine a host name with a `MESH_INTERNAL` `ServiceEntry`, and shows what `MESH_INTERNAL` changes compared with `MESH_EXTERNAL`.

The third part adds a second machine behind the same host, and breaks the selector to show the `503 UH` it causes. Its lab asks you to repair a host whose selector and labels do not match. The fourth part writes the `WorkloadGroup` that real virtual machines register against, and builds the files a real machine needs. Its lab asks you to add two machines to the mesh as one service, starting from nothing.
