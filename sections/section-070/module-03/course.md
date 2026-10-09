# Add External Workloads With WorkloadEntry

Astronaut, some ships in your fleet will never live in Kubernetes. Think of an old freighter that flies outside the fleet's signal network: a database on a virtual machine, an old service nobody has moved into a container, a device with a fixed address. You run it, you own it, but the mesh has never heard of it.

Right now your ships can only reach such a machine by its address, like shouting coordinates into space. Nobody gives it a name, a place on the star chart (the mesh's list of services), or crew papers that mission control recognises. This module fixes that with three Istio objects:

- A **`WorkloadEntry`** describes one machine outside Kubernetes: its address, its labels and the identity it runs as. It is to that machine what a pod is to a container.
- A **`ServiceEntry`** with `location: MESH_INTERNAL` and a `workloadSelector` gives a group of those machines one name, like a beacon that several ships answer to.
- A **`WorkloadGroup`** is a template for many machines, so a real virtual machine can add itself to the star chart when it starts.

> `MESH_EXTERNAL` says "a stranger's ship": you get a name and routing. `MESH_INTERNAL` says "one of ours": the mesh also expects the ship's identity and the secret handshake (mutual TLS).

## How this module is organised

1. **[`WorkloadEntry`: One Old Ship](./course-01-workloadentry-one-instance.md)**: reach a machine by address, and describe it with its first `WorkloadEntry`.
2. **[`MESH_INTERNAL` And The Selector](./course-02-mesh-internal-and-the-selector.md)**: give the machine a name with a `ServiceEntry`, and see what `MESH_INTERNAL` changes.
3. **[Two Ships, One Beacon](./course-03-two-ships-one-beacon.md)**: add a second machine, and find a selector that matches nothing.
4. **[`WorkloadGroup` And Real Onboarding](./course-04-workloadgroup-and-real-onboarding.md)**: the template a real virtual machine registers against, and what that machine needs.

## Learning objectives

After this module you can:

- Describe a machine outside Kubernetes with a `WorkloadEntry`: its address, labels and service account.
- Explain the identity a `serviceAccount` gives that machine, and why it matters.
- Group entries into one service with a `MESH_INTERNAL` `ServiceEntry` and a `workloadSelector`.
- State what `MESH_INTERNAL` changes compared with `MESH_EXTERNAL`, and spot the failed secret handshake it causes when the machine has no sidecar.
- Find a `workloadSelector` that matches no entry from a `503 UH` and the proxy's endpoint list.
- Say what a `WorkloadGroup` is for, and what a real virtual machine needs before it can register itself.

## Before you start

Every mission starts with a pre-flight check, astronaut. Make sure you know the basics below, know what is in your playground, and know where the playground stops being like a real virtual machine.

### What you should already know

- **How the mesh works.** A sidecar proxy (the communications officer) sits beside every pod, and `istiod` (mission control) sends it orders. You read those orders with `istioctl proxy-config`.
- **What a `ServiceEntry` is.** It adds a service that Kubernetes does not know to the mesh's star chart, with `hosts`, `ports`, `location` and `resolution`.
- **Kubernetes basics.** Namespaces, Deployments, ServiceAccounts, pod labels and `kubectl exec`.

### What is in your playground

Your playground is a small training solar system: one `kind` cluster with **Istio 1.30.5** installed. Its sidecars answer name lookups from the star chart (Istio's DNS capture), so a host that only exists in a `ServiceEntry` can still be called by name. Everything you need is on one planet, the namespace **`starfleet`**:

| Ship | Its role |
| --- | --- |
| `shuttle` | **Your shuttle**, with a sidecar (`2/2`). You send every test signal from here, with `curl` |
| `freighter-vm-1`, `freighter-vm-2` | Two **old freighters** standing in for virtual machines. Sidecar injection is switched off (`1/1`), there is no Service in front of them, and they answer HTTP on port `8080`. Their `/hostname` path answers with the pod's name, so you can see which freighter took a signal |
| `freighter` ServiceAccount | The identity both freighters run as |

The freighters' own pod labels are `ship: freighter-vm-1` and `ship: freighter-vm-2`. The label you will give them in the mesh, `app: freighter`, is deliberately different, so you always know which object did the selecting.

No `WorkloadEntry`, `ServiceEntry`, `WorkloadGroup` or `DestinationRule` exists yet. Writing them is your mission.

### Where the stand-in stops being a real virtual machine

A pod without a sidecar is **not** a real virtual machine. It lives on the pod network, and its address changes when the pod restarts. It does not run `istio-agent`, the small program that gives a real machine its sidecar and its identity. What it copies well is the part this module is about: an address that answers, which the mesh knows nothing about.

So three things only work on a real machine, and the parts say so when you meet them:

- The machine cannot **prove** its identity, because no sidecar holds a certificate for it.
- It cannot take part in the **secret handshake** (mutual TLS). You will switch the handshake off for its host with a `DestinationRule`, only because it is a stand-in.
- It cannot **register itself** against a `WorkloadGroup`.

Launch your playground now, and keep it running next to you while you read the parts:

<!-- astrona:playground -->

## Why this matters

The exam topic "connecting to external workloads and services" covers both kinds of outside traffic: other people's services, and your own machines that are not in Kubernetes. For your own machines, a working name is only half the job. The other half is that the mesh treats them as members: they get an identity, the same policies, and the same load balancing and health checks as any pod. This module shows you which field gives you which half, and how to prove it with `istioctl proxy-config`.
