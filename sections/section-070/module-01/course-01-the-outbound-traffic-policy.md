# Part 1 — The Outbound Traffic Policy

> Prerequisite: [the module landing page](./course.md). Next: [Part 2 — The `ServiceEntry` Object](./course-02-the-serviceentry-object.md).

Before the object, the policy. One mesh-wide setting decides whether a destination Istio has never heard of is allowed, and it changes what a `ServiceEntry` is *for* — from a way to gain features to a way to gain permission.

## The default: `ALLOW_ANY`

Out of the box, a sidecar passes traffic to unknown destinations straight through. It does not inspect it, route it, or record much about it. It gets out of the way.

That is a deliberate choice: a mesh that broke every outbound call the moment it was installed would be unusable. The cost is that the mesh has no visibility into, and no control over, where your workloads send data.

> [!TIP]
> **Try it — external calls under the default policy**
>
> ```sh
> kubectl -n istio-system get cm istio -o jsonpath='{.data.mesh}' | grep -A2 outboundTrafficPolicy || echo "(no outboundTrafficPolicy block - the default ALLOW_ANY applies)"
> kubectl -n egress-demo exec deploy/tester -- \
>   curl -s -o /dev/null -w 'httpbin.org:  %{http_code}\n' --max-time 10 http://httpbin.org/get
> kubectl -n egress-demo exec deploy/tester -- \
>   curl -s -o /dev/null -w 'example.com:  %{http_code}\n' --max-time 10 http://example.com/
> ```
>
> Expect something like:
>
> ```text
> (no outboundTrafficPolicy block - the default ALLOW_ANY applies)
> httpbin.org:  200
> example.com:  200
> ```
>
> Both external hosts answer, and the setting may not even appear in the mesh config because the default is implicit. Convenient — and it means a compromised pod can reach anything on the internet with no record in the mesh of where your traffic went.

## `REGISTRY_ONLY` — deny by default

The other mode refuses any destination not in the registry. It is a **mesh-wide** setting under `meshConfig`, so it is applied at install time rather than with a namespaced object:

```sh
istioctl install --set profile=demo \
  --set meshConfig.outboundTrafficPolicy.mode=REGISTRY_ONLY -y
```

That is the setting a security-minded exam task will ask for, and the one that makes `ServiceEntry` necessary rather than merely useful.

Note what "the registry" contains, because it is broader than Kubernetes Services:

- every Kubernetes Service in every watched namespace;
- every `ServiceEntry`;
- every `WorkloadEntry` grouped by a `MESH_INTERNAL` `ServiceEntry` (module 3).

So switching to `REGISTRY_ONLY` does not break in-cluster traffic at all. It breaks exactly the calls nobody declared.

## The signature of a refusal

Under `REGISTRY_ONLY` a blocked call typically fails with **HTTP 502** produced by the sidecar. Recognising that is worth more than the YAML, because the alternatives look similar and mean different things:

| Symptom | Usually means |
| --- | --- |
| `502` from the sidecar | the mesh refused it — the host is not in the registry |
| `000` / connection refused | nothing answered at all — DNS, network, or a `Sidecar` scope (section 010) |
| `504` | a route timeout fired (section 040) |
| DNS resolution failure | the name does not resolve in the cluster at all |

The 502 is a *mesh decision*. DNS worked, the network is fine, and the proxy simply had no cluster to route to.

> [!TIP]
> **Try it — switch the mesh to deny-by-default**
>
> ```sh
> istioctl install --set profile=demo \
>   --set meshConfig.outboundTrafficPolicy.mode=REGISTRY_ONLY -y
> sleep 5
> kubectl -n egress-demo exec deploy/tester -- \
>   curl -s -o /dev/null -w 'httpbin.org:  %{http_code}\n' --max-time 10 http://httpbin.org/get
> kubectl -n egress-demo exec deploy/tester -- \
>   curl -s -o /dev/null -w 'kubernetes:   %{http_code}\n' --max-time 10 http://kubernetes.default.svc:443/ 2>/dev/null
> ```
>
> Expect something like:
>
> ```text
> ✔ Istio core installed
> ✔ Istiod installed
> ...
> httpbin.org:  502
> kubernetes:   400
> ```
>
> The install takes a minute and **reconciles** the existing control plane rather than creating a second one — the same declarative behaviour as any other `istioctl install`. The external call that returned `200` now returns `502`, while an in-cluster host still answers (with whatever that host says — `400` here is the API server objecting to the request, which is fine; the point is that it was reached). Nothing about the pod or the network changed.

## Per-namespace override

`outboundTrafficPolicy` also exists on the `Sidecar` resource from section 010, which lets one namespace differ from the mesh default:

```yaml
apiVersion: networking.istio.io/v1
kind: Sidecar
metadata:
  name: default
  namespace: egress-demo
spec:
  egress:
    - hosts:
        - "./*"
        - "istio-system/*"
  outboundTrafficPolicy:
    mode: REGISTRY_ONLY
```

That is the practical migration path: turn the mesh default to `REGISTRY_ONLY` eventually, but start by tightening one namespace at a time, where you can enumerate its external dependencies without breaking everybody.

> *Under `REGISTRY_ONLY` a 502 from the sidecar means "not in the registry" — DNS and the network are fine.*

## Reference

- [Accessing external services](https://istio.io/latest/docs/tasks/traffic-management/egress/egress-control/) — the task page covering both modes.
- [MeshConfig `outboundTrafficPolicy`](https://istio.io/latest/docs/reference/config/istio.mesh.v1alpha1/#MeshConfig-OutboundTrafficPolicy) — the two values and where the setting lives.
- [Sidecar `outboundTrafficPolicy`](https://istio.io/latest/docs/reference/config/networking/sidecar/#OutboundTrafficPolicy) — the per-namespace override.
- `kubectl -n istio-system get cm istio -o jsonpath='{.data.mesh}'` — the live mesh configuration, to check which mode is actually in force.
