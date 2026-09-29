# `MESH_INTERNAL` And The Selector

> Prerequisite: [`WorkloadEntry`: One Instance](./course-01-workloadentry-one-instance.md). Next: [`WorkloadGroup` And Real Onboarding](./course-03-workloadgroup-and-real-onboarding.md).

A `WorkloadEntry` on its own is not reachable by name. This part is the object that gives a group of them a hostname and ports — the same `ServiceEntry` from module 1, with two fields changed and one added.

## The object

```yaml
apiVersion: networking.istio.io/v1
kind: ServiceEntry
metadata:
  name: legacy
  namespace: vm-demo
spec:
  hosts:
    - legacy.vm-demo.svc
  location: MESH_INTERNAL
  resolution: STATIC
  ports:
    - number: 8080
      name: http
      protocol: HTTP
  workloadSelector:
    labels:
      app: legacy-backend
```

## What changed from module 1

| Field | External service (module 1) | Your own external workload |
| --- | --- | --- |
| `location` | `MESH_EXTERNAL` | **`MESH_INTERNAL`** |
| `resolution` | `DNS` — resolve the public name | **`STATIC`** — use declared addresses |
| endpoints | implied by DNS | **`workloadSelector`** matching `WorkloadEntry` labels |

**`workloadSelector`** is the join. It selects `WorkloadEntry` objects **in the same namespace** by their labels, exactly as a Kubernetes Service selects pods. Add a second `WorkloadEntry` with the same labels and the service gains a second endpoint, with no change to this object.

Note it selects entries, not pods — though a `workloadSelector` can in fact match pods too, which is how a single service can span VMs and Kubernetes workloads during a migration.

**`resolution: STATIC`** follows from that. The addresses are declared in the entries, so there is nothing to resolve. Using `DNS` here is a common mistake: it tells the proxy to resolve `legacy.vm-demo.svc`, which resolves nowhere, and the selector is then ignored.

## What `MESH_INTERNAL` actually changes

This is the examinable distinction, and it is worth being concrete rather than saying "it is internal".

| | `MESH_EXTERNAL` | `MESH_INTERNAL` |
| --- | --- | --- |
| Named host, routing, `VirtualService` | ✅ | ✅ |
| `DestinationRule` policy (pools, outlier detection) | ✅ | ✅ |
| Treated as a mesh member | ❌ | ✅ |
| mTLS attempted to the workload | ❌ | ✅ |
| Workload identity from `serviceAccount` | ❌ | ✅ |
| `AuthorizationPolicy` can name it | ❌ | ✅ |
| Telemetry attributes it as a mesh workload | ❌ | ✅ |

The rows that matter are the bottom four. `MESH_EXTERNAL` would give you the hostname and the routing — which is why a configuration using it *appears* to work — and none of the identity. A task that says "the VM must be subject to the same authorization policy as the pods" is testing exactly this field.

The mTLS row carries a practical consequence: with `MESH_INTERNAL`, Istio expects to speak mTLS to the workload, which a real VM can only do if it is running `istio-agent`. In this playground the stand-in is not, so traffic falls back to plaintext — fine for a lab, and one more place the analogy stops.

> [!TIP]
> **Try it — give the workload a name and a place in the registry**
>
> ```sh
> VM_IP=$(kubectl -n vm-demo get pod -l app=legacy-backend -o jsonpath='{.items[0].status.podIP}')
> kubectl apply -f - <<EOF
> apiVersion: networking.istio.io/v1
> kind: WorkloadEntry
> metadata:
>   name: legacy-vm-1
>   namespace: vm-demo
> spec:
>   address: $VM_IP
>   labels:
>     app: legacy-backend
>   serviceAccount: legacy-sa
> ---
> apiVersion: networking.istio.io/v1
> kind: ServiceEntry
> metadata:
>   name: legacy
>   namespace: vm-demo
> spec:
>   hosts:
>     - legacy.vm-demo.svc
>   location: MESH_INTERNAL
>   resolution: STATIC
>   ports:
>     - number: 8080
>       name: http
>       protocol: HTTP
>   workloadSelector:
>     labels:
>       app: legacy-backend
> EOF
> sleep 3
> kubectl -n vm-demo exec deploy/tester -- \
>   curl -s -o /dev/null -w 'by name: %{http_code}\n' --max-time 10 http://legacy.vm-demo.svc:8080/get
> ```
>
> Expect something like:
>
> ```text
> workloadentry.networking.istio.io/legacy-vm-1 created
> serviceentry.networking.istio.io/legacy created
> by name: 200
> ```
>
> Note the heredoc is **unquoted** (`<<EOF`) so the shell substitutes `$VM_IP` — the address has to be baked in, which is the practical difference between declaring a VM and labelling a pod. The call now works **by hostname**, which it could not do at all before.

## Seeing it as a first-class endpoint

The `200` is not the interesting evidence — that worked by IP in Part 1. The interesting evidence is that the workload is now a registered cluster with an endpoint, which is what every `DestinationRule` and `AuthorizationPolicy` in the mesh operates on.

> [!TIP]
> **Try it — the workload in the proxy's registry**
>
> ```sh
> kubectl -n vm-demo get workloadentry,serviceentry
> istioctl proxy-config cluster deploy/tester -n vm-demo | grep -i legacy
> istioctl proxy-config endpoints deploy/tester -n vm-demo | grep -i legacy
> ```
>
> Expect something like:
>
> ```text
> NAME                                            AGE
> workloadentry.networking.istio.io/legacy-vm-1   40s
> serviceentry.networking.istio.io/legacy         40s
> legacy.vm-demo.svc     8080     -     outbound     STATIC
> 10.244.0.31:8080       HEALTHY   OK    outbound|8080||legacy.vm-demo.svc
> ```
>
> Compare with the `0` from Part 1's checkpoint. The host is now a `STATIC` cluster with the declared address as its endpoint — meaning `VirtualService` rules, `DestinationRule` policy, outlier detection and telemetry all apply to it exactly as they would to a Deployment.

## Adding a second instance

Because the join is by label, scaling the declared service is adding another object:

```yaml
apiVersion: networking.istio.io/v1
kind: WorkloadEntry
metadata:
  name: legacy-vm-2
  namespace: vm-demo
spec:
  address: 10.0.4.19
  labels:
    app: legacy-backend      # same labels → same service
  serviceAccount: legacy-sa
```

The `ServiceEntry` is untouched; its `workloadSelector` picks up the new entry and the cluster gains a second endpoint. Load balancing, outlier detection and locality settings then apply across both, exactly as they would across two pods.

That is the shape you would use for a small, stable fleet. For a fleet that changes, writing entries by hand does not work — which is Part 3.

> *`MESH_INTERNAL` plus a `workloadSelector` turns declared machines into an ordinary mesh service, with identity attached.*

## Common pitfalls

> [!WARNING]
> **Leaving `location` at `MESH_EXTERNAL` for a workload you own.** `MESH_INTERNAL` is what makes mTLS and identity apply; without it the instance is treated as a third-party endpoint.
>
> **Writing `endpoints` and a `workloadSelector` on the same `ServiceEntry`.** They are alternative ways of supplying the same thing.
>
> **Expecting the selector to match pods.** It matches `WorkloadEntry` labels, in the same namespace.
>
> **Assuming adding an instance needs a new `ServiceEntry`.** A second `WorkloadEntry` with matching labels joins the same service automatically.

## Reference

- [ServiceEntry API](https://istio.io/latest/docs/reference/config/networking/service-entry/) — `location`, `resolution` and `workloadSelector`.
- [Virtual machine installation](https://istio.io/latest/docs/setup/install/virtual-machine/) — the full onboarding procedure these objects are part of.
- [Istio identity](https://istio.io/latest/docs/concepts/security/#istio-identity) — what `MESH_INTERNAL` plus a service account yields.
- `istioctl proxy-config endpoints <workload>` — confirming the selector actually matched something.
