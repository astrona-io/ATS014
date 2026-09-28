# `WorkloadGroup` And Real Onboarding

> Prerequisite: [`MESH_INTERNAL` And The Selector](./course-02-mesh-internal-and-the-selector.md). Next: [the module landing page](./course.md).

Writing a `WorkloadEntry` per machine does not scale and does not survive autoscaling. This part is the object that fixes that, what a real VM needs for it to work, and an honest account of where this playground stops.

## The problem with hand-written entries

Two failures, both structural:

- **A new instance has an address nobody declared.** Until someone writes a `WorkloadEntry`, the new VM is invisible to the mesh — even though it is serving traffic.
- **A terminated instance leaves a stale entry.** The cluster keeps an endpoint that no longer exists, and callers get connection failures until someone notices.

Neither is a configuration mistake. They are the consequence of a human being the registration mechanism.

## `WorkloadGroup` — a template plus a lifecycle

```yaml
apiVersion: networking.istio.io/v1
kind: WorkloadGroup
metadata:
  name: legacy
  namespace: vm-demo
spec:
  metadata:
    labels:
      app: legacy-backend
  template:
    serviceAccount: legacy-sa
    ports:
      http: 8080
```

It describes what instances of a service **look like** — labels, service account, ports, optionally a readiness probe — without naming any address. A VM running `istio-agent` then **registers itself** against the group at startup, and Istio creates the `WorkloadEntry` automatically. When the instance goes away, the entry is removed.

The relationships are worth stating plainly, because the three object names blur together:

```text
  WorkloadGroup   is to   WorkloadEntry    as   Deployment  is to  Pod
      (template + lifecycle)                        (template + lifecycle)

  ServiceEntry with workloadSelector       as   Service     is to  Pods
      (a name and ports in front of whatever matches)
```

So a fully automated setup has **two** hand-written objects — the `WorkloadGroup` and the `ServiceEntry` — and zero per-instance objects.

## What a real VM needs

Auto-registration is not configuration alone. Before a machine can register, it needs:

| Requirement | Why |
| --- | --- |
| `istio-agent` installed and running | it is what connects to the control plane and registers |
| A **token** provisioned onto the machine | it proves the machine may assume the group's service account |
| The mesh **root certificate** | to trust the control plane |
| A `cluster.env` / mesh config file | trust domain, network, the control plane address |
| Network reachability to `istiod` (port 15012) | the xDS connection |
| The VM's address routable from the pod network | otherwise nothing can reach it once registered |

`istioctl x workload entry configure` generates the first four into a bundle you copy onto the machine. The full procedure is Istio's "virtual machine installation" guide and is a larger topic than this module — but knowing the **shape** of it (agent, token, root cert, config, connectivity) is enough for the exam, and enough to know whether a proposed answer is plausible.

## What this playground cannot show

Stated plainly, because inventing a demonstration would teach the wrong thing.

The stand-in is a pod with injection disabled. It faithfully reproduces "a reachable address the mesh knows nothing about", and everything in Parts 1 and 2 works on it exactly as it would on a VM. What it **cannot** do:

- **Auto-register.** It does not run `istio-agent`, has no token, and has no way to talk to `istiod`. Creating a `WorkloadGroup` here is a configuration exercise — the object is valid, and no entry will ever appear from it.
- **Prove its identity.** Part 1's `serviceAccount` is a declaration. A real VM presents a token and receives a certificate; nothing here does.
- **Speak mTLS.** `MESH_INTERNAL` makes Istio expect mutual TLS to the workload, and the stand-in cannot. Traffic falls back to plaintext.

If you want to see auto-registration, it needs a real machine. What you can do here is write the `WorkloadGroup`, read its `template` against the `WorkloadEntry` you wrote by hand, and confirm that the second is exactly what the first would have produced.

> [!TIP]
> **Try it — the template beside the instance it would create**
>
> ```sh
> kubectl apply -f - <<'EOF'
> apiVersion: networking.istio.io/v1
> kind: WorkloadGroup
> metadata:
>   name: legacy
>   namespace: vm-demo
> spec:
>   metadata:
>     labels:
>       app: legacy-backend
>   template:
>     serviceAccount: legacy-sa
>     ports:
>       http: 8080
> EOF
> kubectl -n vm-demo get workloadgroup,workloadentry
> kubectl -n vm-demo get workloadentry -o custom-columns=NAME:.metadata.name,ADDRESS:.spec.address,SA:.spec.serviceAccount,LABELS:.spec.labels
> ```
>
> Expect something like:
>
> ```text
> workloadgroup.networking.istio.io/legacy created
> NAME                                             AGE
> workloadgroup.networking.istio.io/legacy         3s
> workloadentry.networking.istio.io/legacy-vm-1    6m
> NAME          ADDRESS       SA          LABELS
> legacy-vm-1   10.244.0.31   legacy-sa   map[app:legacy-backend]
> ```
>
> One group, one entry — and the entry is still the one **you** wrote six minutes ago. No new entry appeared and none will, because nothing here can register. Compare the group's `template` with the entry's fields: same service account, same labels, same port. That correspondence is what auto-registration would fill in, with the address supplied by the machine itself.

## Common pitfalls

> [!WARNING]
> **Using `MESH_EXTERNAL` for your own workload.** You get routing but no identity, so no `AuthorizationPolicy` and no mTLS. The configuration appears to work, which is what makes this worth checking.
>
> **`resolution: DNS` with a `workloadSelector`.** Selecting `WorkloadEntry` objects means the addresses are declared, so the resolution is `STATIC`. With `DNS` the proxy tries to resolve a hostname that resolves nowhere.
>
> **Labels that do not match.** The `ServiceEntry`'s `workloadSelector.labels` must match the `WorkloadEntry`'s `labels`. A mismatch gives a host with zero endpoints — 503 at request time, no validation error.
>
> **Omitting `serviceAccount`.** No identity, so policies that name principals cannot match the workload.
>
> **Expecting a `WorkloadEntry` to create connectivity.** It declares a workload. The address must already be routable from the pod network.
>
> **Confusing `WorkloadGroup` with `WorkloadEntry`.** The group is a template for auto-registration; the entry is one concrete instance.
>
> **Expecting a `WorkloadGroup` alone to produce endpoints.** Nothing appears until a machine registers against it.
>
> **Forgetting the ServiceAccount object must exist.** `serviceAccount: legacy-sa` refers to a real Kubernetes ServiceAccount in the same namespace.

> *`WorkloadGroup` is to `WorkloadEntry` what a Deployment is to a Pod — and like a Deployment, it needs something on the other end that actually registers.*

## Reference

- [WorkloadGroup API](https://istio.io/latest/docs/reference/config/networking/workload-group/) — the template, including the readiness probe.
- [Virtual machine installation](https://istio.io/latest/docs/setup/install/virtual-machine/) — the full onboarding procedure, including `istioctl x workload entry configure`.
- [Virtual machine architecture](https://istio.io/latest/docs/ops/deployment/vm-architecture/) — how the agent, the token and the control plane fit together.
- [Bookinfo with a virtual machine](https://istio.io/latest/docs/examples/virtual-machines/) — a worked end-to-end example on real machines.
