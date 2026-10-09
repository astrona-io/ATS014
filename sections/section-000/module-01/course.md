# How A Request Moves Through The Mesh

Astronaut, almost everything you will do with Istio is giving orders to a proxy. This module is about that proxy itself: the communications officer on board every spaceship (pod). Where does it come from? How do signals (requests) end up passing through it? Who gives it its orders? And how do you ask it what it currently believes?

None of it is configuration you write. It is what exists the moment a planet (a namespace) is switched on for Istio. Most confusing results with Istio come from mixing up four parts that sit close together:

> A **Service** groups pods. **kube-proxy** would pick one of them at random. **istiod** writes the orders. The **istio-proxy sidecar** actually decides where a signal goes, and it decides in the pod that *sent* the signal.

In space terms: the Service is a beacon that a group of ships answers to, `istiod` is mission control, and the sidecar is the communications officer on the ship that *sends* the signal. Mission control gives the orders, but the communications officer on the sending ship makes the call.

## Learning objectives

After this module you can:

- Explain what sidecar injection adds to a pod, and why a namespace label alone does not change running pods.
- Tell an injected pod from an uninjected one, and bring a workload into the mesh.
- Describe how outgoing and incoming signals reach the proxy without the application knowing.
- Say which side of a call decides routing, and what a sender without a proxy loses.
- Expand LDS, RDS, CDS and EDS, and say which one carries a given kind of order.
- Follow one signal down the listener, route, cluster and endpoint chain, and read the output of each layer.
- Read an Envoy cluster name: direction, port, subset and host.
- Pick the right diagnostic command for a symptom, and say what each one cannot see.
- Read a response flag such as `NR`, `NC` or `UH`, and say which half of the setup to look at.

## Before you start

Every mission starts with a pre-flight check, astronaut. Make sure you have the knowledge this module expects, and know what is waiting in your playground.

### What you should already know

- **Kubernetes basics.** Namespaces, Deployments, Services, pod labels, `kubectl logs` and `kubectl exec`, on a cluster where you have administrator rights.
- **No Istio yet.** This module starts from zero, and you write no Istio objects in it.

### What is in your playground

Your playground is a small training solar system: one `kind` cluster with **Istio 1.30.5** already installed, and `istioctl` ready to use. It has two planets, chosen to contrast with each other.

**`starfleet`** has injection switched on, so every ship on it has a communications officer. The fleet on it is the Starfleet, the Istio docs' Bookinfo sample with space names:

| Ship | Its role in the fleet |
| --- | --- |
| `bridge` | The flagship: the page astronauts see. It signals the other ships to build it |
| `cargo` | The supply ship: answers with facts about an item |
| `scout` v1, v2, v3 | Three ship classes of the same scout |
| `navcom` | The navigation computer the scouts ask for a rating |
| `shuttle` | Your shuttle: you send test signals from here |
| `probe` v1, v2 | The echo probe, on port `8000`. It sends back what it receives |

**`outpost`** has injection switched **off**, on purpose. Its one ship, the `drifter`, runs the same client image as the shuttle but has no communications officer on board.

There is no `VirtualService`, no `DestinationRule` and no policy of any kind. That is the point: this module is about what the mesh does before you configure anything.

Launch your playground now, and keep it running next to you while you read the parts:

<!-- astrona:playground -->

## Why this matters

Everything else you do with Istio gives orders to the communications officer, and you prove those orders arrived with the commands from this module: `istioctl proxy-status`, `istioctl proxy-config` and the flight log. Learn how the proxy gets on board and how it receives its orders, and every result you see later has an explanation you can check.
