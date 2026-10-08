# Where Locality Comes From

Every setting in this module selects over localities (which orbit a ship flies in), so the first question is where an endpoint's locality comes from and how to check it has one. Getting this wrong wastes more time than any other mistake here, because every subsequent configuration silently does nothing.

## Three labels, one hierarchy

Istio composes an endpoint's locality from three **node** labels:

| Label | Level | Example |
| --- | --- | --- |
| `topology.kubernetes.io/region` | region — the coarsest | `us-east1` |
| `topology.kubernetes.io/zone` | zone within a region | `us-east1-b` |
| `topology.istio.io/subzone` | subzone within a zone — Istio-specific, optional | `rack-3` |

The first two are set automatically by every managed Kubernetes provider. The third has no Kubernetes equivalent and exists because Istio wanted a third level for racks, failure domains or cells.

They compose into a slash-separated string:

```text
   us-east1 / us-east1-b / rack-3
   └─region─┘ └───zone───┘ └subzone┘

   written with wildcards in configuration:
   us-east1/*           all zones in the region
   us-east1/us-east1-b/* one zone, any subzone
```

**Every pod inherits the locality of the node it runs on.** There is no per-pod setting in the normal case — locality is a property of where the workload landed, which is why it needs no coordination.

## The `istio-locality` override

When node labels are absent or wrong — a bare-metal cluster, a local development cluster, a node pool somebody forgot to label — a pod can declare its own locality with the **`istio-locality`** label on the pod template:

```yaml
template:
  metadata:
    labels:
      app: httpbin
      istio-locality: local.zone-a
```

Two details:

- **The separator is `.`, not `/`.** A Kubernetes label value cannot contain a slash, so `region.zone.subzone` is the encoding. `local.zone-a` means region `local`, zone `zone-a`.
- **It overrides the node-derived value** for that pod. That makes it useful for testing and for pinning a workload's declared locality independently of scheduling, and it is what this playground uses.

## Checking before configuring

This is the step to do first, every time. If endpoints have no locality, nothing in Part 2 will do anything and there will be no error message telling you so.

> [!TIP]
> **Try it — the locality attached to each endpoint**
>
> ```sh
> kubectl get nodes -L topology.kubernetes.io/region,topology.kubernetes.io/zone
> istioctl proxy-config endpoints deploy/tester -n locality-demo \
>   --cluster "outbound|8000||httpbin.locality-demo.svc.cluster.local" -o json \
>   | grep -E '"region"|"zone"|"address"'
> ```
>
> Expect something like:
>
> ```text
> NAME                 STATUS   REGION   ZONE
> astro-...-control-plane   Ready    local    zone-a
> "address": "10.244.0.21",
> "region": "local",
> "zone": "zone-a",
> "address": "10.244.0.22",
> "region": "local",
> "zone": "zone-b",
> ```
>
> Two endpoints, two different localities — even though both pods are on the one node, because the `istio-locality` label overrides what the node says. **If every endpoint shows an empty locality, stop here.** The cause is missing node labels or a missing `istio-locality` label, not your `DestinationRule`, and no amount of `localityLbSetting` will help.

## Where the caller's locality comes from

One point that is easy to skip over: locality-aware routing compares the **caller's** locality with each endpoint's. The caller's locality is derived the same way — from its own node labels, or its own `istio-locality` label.

So "prefer local" is meaningful only if the calling workload has a locality too. A client with no locality has nothing to be near, and the preference has no effect for it. On a real cluster this is automatic; in a hand-built test environment it is a thing to check on both sides.

> [!TIP]
> **Try it — the caller has a locality too**
>
> ```sh
> kubectl -n locality-demo get pod -l app=tester -o jsonpath='{.items[0].spec.nodeName}{"\n"}'
> kubectl -n locality-demo get pod -l app=tester \
>   -o jsonpath='{.items[0].metadata.labels}{"\n"}' | tr ',' '\n' | grep -i locality
> istioctl proxy-config endpoints deploy/tester -n locality-demo --cluster "outbound|8000||httpbin.locality-demo.svc.cluster.local"
> ```
>
> Expect something like:
>
> ```text
> astro-ats-014-playground-040-04-control-plane
> 10.244.0.21:8080     HEALTHY     OK      outbound|8000||httpbin...
> 10.244.0.22:8080     HEALTHY     OK      outbound|8000||httpbin...
> ```
>
> The `tester` pod has no `istio-locality` label of its own, so its locality comes from the node — `local/zone-a` here. That makes `zone-a` the "local" zone from its point of view, which is what the preference in Part 2 will act on. Both endpoints are `HEALTHY` and `OK` right now; module 3's `OUTLIER CHECK` column is the one Part 3 depends on.

## Common pitfalls

> [!WARNING]
> **Expecting locality to be configured per pod.** It is inherited from the node's `topology.kubernetes.io` labels. `istio-locality` is the override for when those are missing or wrong.
>
> **Setting `istio-locality` on the Deployment rather than the pod template.** It has to land on the pods; a label on the Deployment's own metadata does nothing.
>
> **Assuming subzone is always present.** Most clusters set region and zone only, and `region/zone` with an empty subzone is normal.
>
> **Changing the label and expecting running pods to update.** Locality is read when the pod is registered. Existing pods keep the locality they started with.

> *Locality comes from node labels, `istio-locality` overrides it per pod, and an endpoint with no locality makes every setting in this module a no-op.*
