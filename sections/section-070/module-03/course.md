# Add External Workloads With WorkloadEntry

<!-- astrona:playground -->
> [!NOTE]
> 🧪 **Hands-on playground for this module** — a clean, throwaway machine to explore on. No task, no grading. Folder: `playground/`
>
> ```sh
> astrona run --git ssh://git@github.com/astrona-io/ATS014.git -c sections/section-070/module-03/playground
> astrona destroy ats-014-playground-070-03
> ```

Astronaut, the previous two modules dealt with services somebody else runs: planets in other solar systems that you signal but cannot change. This module is about something different: a workload **you** run that simply is not in Kubernetes. Think of an old ship that flies outside the fleet's signal network: a database on a VM, a legacy service nobody has containerised, an appliance with a fixed address.

The distinction matters because you want more from your own workload than from a third party's. Calling it by a stable hostname instead of an IP is the obvious part. Giving it a mesh **identity** (crew papers mission control recognises), so the same `AuthorizationPolicy` and `PeerAuthentication` rules that govern your spaceships govern it too, is the part that makes this feature worth learning.

> `MESH_EXTERNAL` gets you routing. `MESH_INTERNAL` additionally gets you identity and policy.

## How this module is organised

1. **[`WorkloadEntry`: One Instance](./course-01-workloadentry-one-instance.md)** — the three fields that describe a non-Kubernetes instance, and the identity the third one produces.
2. **[`MESH_INTERNAL` And The Selector](./course-02-mesh-internal-and-the-selector.md)** — turning entries into a named service, and what `MESH_INTERNAL` changes compared with module 1.
3. **[`WorkloadGroup` And Real Onboarding](./course-03-workloadgroup-and-real-onboarding.md)** — auto-registration, what a real VM needs, an honest account of what this playground cannot show, and the module's pitfalls.

## Learning objectives

After this module you can:

- Describe a non-Kubernetes instance with a `WorkloadEntry`, including its address, labels and service account.
- Explain the SPIFFE identity a `serviceAccount` produces and why it matters.
- Group entries into a service with a `MESH_INTERNAL` `ServiceEntry` and a `workloadSelector`.
- State precisely what `MESH_INTERNAL` provides that `MESH_EXTERNAL` does not.
- Say what a `WorkloadGroup` is for and when to use it instead of writing entries by hand.
- Name what a real VM needs before it can auto-register.

## Before you start

This module assumes [section 000](../../section-000/module-01/course.md): a proxy beside every pod, `istiod` programming it over xDS, and `istioctl proxy-config` as the way to see what a proxy actually holds rather than what you hoped it holds.

You need `ServiceEntry` from module 1. This module reuses it with a different `location` and a selector.

The playground gives you a single-node `kind` cluster with **Istio 1.30.5 already installed** (the `demo` profile) and the namespace **`vm-demo`**, injected, containing:

- `tester` — a client pod with `curl` and a sidecar.
- `legacy-backend` — a pod **deliberately excluded from injection** with the label `sidecar.istio.io/inject: "false"`. It stands in for a virtual machine: it has an IP address, answers HTTP on 8080, and has no sidecar, no Service and no mesh membership.
- `legacy-sa` — a ServiceAccount the stand-in runs as, so identity has something to point at.

A pod with injection disabled is **not** the same thing as a real VM — it is on the pod network and it does not run `istio-agent`. What it reproduces faithfully is the part this module is about: a reachable address the mesh knows nothing about. Part 3 says exactly where the analogy stops.

No `WorkloadEntry`, `ServiceEntry` or `WorkloadGroup` exists yet.

## Where this fits

This is the last of the three external-traffic modules and the one that closes the loop: modules 1 and 2 brought other people's services into the mesh's view, and this one brings your own non-Kubernetes workloads into its *membership*. The payoff is a single policy and identity model covering spaceships and old machines alike, which is what "mesh expansion" means in Istio's own documentation.
