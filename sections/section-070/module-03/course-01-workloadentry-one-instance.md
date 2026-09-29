# `WorkloadEntry`: One Instance

> Prerequisite: [the module landing page](./course.md). Next: [`MESH_INTERNAL` And The Selector](./course-02-mesh-internal-and-the-selector.md).

One object describing one machine. Three fields, and the third is the one that separates this module from the previous two.

## Reachable, and anonymous

Start from what you have. The stand-in workload has an IP and answers requests, and the mesh knows nothing about it.

> [!TIP]
> **Try it — reachable, but anonymous**
>
> ```sh
> VM_IP=$(kubectl -n vm-demo get pod -l app=legacy-backend -o jsonpath='{.items[0].status.podIP}')
> echo "stand-in VM address: $VM_IP"
> kubectl -n vm-demo exec deploy/tester -- \
>   curl -s -o /dev/null -w 'by address: %{http_code}\n' --max-time 10 "http://$VM_IP:8080/get"
> istioctl proxy-config cluster deploy/tester -n vm-demo | grep -c legacy
> kubectl -n vm-demo get pods -o wide
> ```
>
> Expect something like:
>
> ```text
> stand-in VM address: 10.244.0.31
> by address: 200
> 0
> NAME                      READY   STATUS    IP
> legacy-backend-...        1/1     Running   10.244.0.31
> tester-...                2/2     Running   10.244.0.32
> ```
>
> The call works — flat pod networking carries it — but the `0` is the interesting number: the client proxy has **no cluster** for this workload. Note also `1/1` versus `2/2`: the stand-in has no sidecar. There is no hostname to call it by, no policy that can name it, no telemetry attributing traffic to it, and if its address changes every caller breaks.

## The object

```yaml
apiVersion: networking.istio.io/v1
kind: WorkloadEntry
metadata:
  name: legacy-vm-1
  namespace: vm-demo
spec:
  address: 10.244.0.31
  labels:
    app: legacy-backend
  serviceAccount: legacy-sa
```

A `WorkloadEntry` is, in effect, a **manually written pod record**. Three fields, each with a clear job:

- **`address`** — where the instance is. For a real VM this is its routable IP, and it must be reachable from the pod network. The object declares a workload; it does not create connectivity.
- **`labels`** — how a `ServiceEntry` will select it, exactly as a Kubernetes Service selects pods by label. Part 2 uses these.
- **`serviceAccount`** — the identity the workload gets, and the reason this is not just a fancy DNS entry.

There are further fields — `network` for multi-network meshes, `locality` (which feeds section 040 module 4's locality settings), `weight`, and `ports` for port remapping — but the three above are what a task will ask for.

**One entry describes one instance.** Several instances of the same service means several entries carrying the same labels.

## What `serviceAccount` buys you

This is the field that makes the workload a first-class mesh member.

Istio issues the workload a **SPIFFE identity** — the same identity format every pod in the mesh gets:

```text
spiffe://<trust-domain>/ns/<namespace>/sa/<service-account>

for this entry:
spiffe://cluster.local/ns/vm-demo/sa/legacy-sa
```

That is exactly the shape a pod running under `legacy-sa` in `vm-demo` would have. The consequence is that every policy that names identities applies to it:

| Object | Can now name this workload |
| --- | --- |
| `AuthorizationPolicy` | `source.principals` / `to` rules |
| `PeerAuthentication` | mTLS requirements |
| Telemetry and access logs | attributed to a named identity rather than a bare IP |

Omit `serviceAccount` and you get a reachable, named endpoint with no identity — policies that reference principals simply cannot match it. That is the difference between "the mesh can route to it" and "the mesh can govern it".

For a **real** VM the identity is not merely declared — the VM proves it, by presenting a token at startup and receiving a certificate. Part 3 covers what that requires. In this playground the declaration is all there is, which is one of the places the stand-in stops being faithful.

## Where it lives

A `WorkloadEntry` is a **namespaced** object, and the namespace matters twice: it is part of the SPIFFE identity, and the `serviceAccount` it names must exist in that same namespace.

```sh
kubectl -n vm-demo get serviceaccount legacy-sa
```

That ServiceAccount is a real Kubernetes object. It does not need to be used by any pod — it exists so the identity has something to refer to, and so RBAC and policy can be written against a name rather than an invention.

> *`address` makes it reachable, `labels` make it selectable, and `serviceAccount` makes it governable.*

## Common pitfalls

> [!WARNING]
> **Expecting a `WorkloadEntry` alone to be reachable by name.** It describes one instance. A `ServiceEntry` with a `workloadSelector` is what puts a name and ports in front of it.
>
> **Leaving `serviceAccount` out.** The workload stays anonymous: no SPIFFE identity, so no `AuthorizationPolicy` or `PeerAuthentication` can name it.
>
> **Creating it in the wrong namespace.** The identity it receives encodes the namespace, so the object's location is part of its meaning.
>
> **Treating it as a substitute for network reachability.** The address still has to be routable from the mesh.

## Reference

- [WorkloadEntry API](https://istio.io/latest/docs/reference/config/networking/workload-entry/) — every field, including `network`, `locality` and `weight`.
- [Virtual machine architecture](https://istio.io/latest/docs/ops/deployment/vm-architecture/) — how Istio models non-Kubernetes workloads.
- [SPIFFE ID format in Istio](https://istio.io/latest/docs/concepts/security/#istio-identity) — the identity string this field produces.
- `kubectl get workloadentry -A` — auto-registered entries appear here too, which Part 3 explains.
