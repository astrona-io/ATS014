# Read Endpoint Locality From Node And Pod Labels

Every locality setting in Istio chooses between endpoints by where they run. An **endpoint** is one pod address (IP address and port) behind a Service. The **locality** of an endpoint is the region, zone and subzone it runs in. If an endpoint has no locality, or the wrong one, every locality setting silently does nothing, and no error message warns you.

So the first job is to learn where the locality comes from, and how to check it. This part shows the labels Istio reads, the pod label that overrides them, and the commands that show the locality the client's sidecar proxy really uses.

## Three labels, one order

Istio builds an endpoint's locality from three labels on the **node** that runs the pod:

| Label | Level | Example |
| --- | --- | --- |
| `topology.kubernetes.io/region` | region, the largest area | `us-east1` |
| `topology.kubernetes.io/zone` | zone inside a region | `us-east1-b` |
| `topology.istio.io/subzone` | subzone inside a zone, Istio only, optional | `rack-3` |

Managed Kubernetes clusters set the first two labels for you. Istio added the third label so you can describe a smaller unit inside a zone, such as a rack.

Together the three values form one locality, written with slashes:

```text
   us-east1 / us-east1-b / rack-3
   └─region─┘ └───zone───┘ └subzone┘

   with wildcards in configuration:
   us-east1/*             every zone in the region
   us-east1/us-east1-b/*  one zone, any subzone
```

**Every pod takes the locality of the node it runs on.** In the normal case you set nothing per pod. The scheduler places the pod on a node, and the node's labels give the pod its locality.

## The `istio-locality` override

Sometimes the node labels are missing or wrong, for example on a bare-metal cluster or a local test cluster. In that case a pod can set its own locality with the **`istio-locality`** label on its pod template:

```yaml
template:
  metadata:
    labels:
      app: probe
      istio-locality: local.zone-b
```

Two details matter here. First, **the separator is a dot, not a slash.** A Kubernetes label value cannot contain `/`, so the format is `region.zone.subzone`, and `local.zone-b` means region `local`, zone `zone-b`. Second, the label **overrides the node's locality** for that pod, and only for that pod. Your playground uses it to put two probes on one node into two different zones.

The label must sit on the **pod template**, not on the Deployment's own `metadata`. Istio reads it when the pod starts. If you change the label, Kubernetes must create new pods, so the Deployment rolls out again.

## Check the localities before you configure anything

Now that you know where the locality comes from, check it on a live cluster. Do this first, every time. If the endpoints have no locality, nothing later in this module works, and no error message tells you why.

<!-- astrona:playground:renew -->

### Look at the node and the endpoints

List the node with its region and zone labels:

```sh
kubectl get nodes -L topology.kubernetes.io/region,topology.kubernetes.io/zone
```

```text
NAME                                       STATUS   ROLES           AGE   VERSION   REGION   ZONE
astro-ats-014-pilot-040-04-control-plane   Ready    control-plane   65s   v1.37.0   local    zone-a
```

Your node name will end in `playground-040-04-control-plane`. The node is in region `local`, zone `zone-a`.

Next, ask the sidecar proxy of `shuttle` which locality each probe endpoint has. `istioctl proxy-config endpoints` prints the endpoint list that `istiod` sent to that proxy, and `-o json` includes the locality of each endpoint:

```sh
istioctl proxy-config endpoints deploy/shuttle -n starfleet \
  --cluster "outbound|8000||probe.starfleet.svc.cluster.local" -o json \
  | grep -E '"region"|"zone"|"address"'
```

You should see (trimmed to the matching lines):

```text
                "address": {
                        "address": "10.244.0.7",
                    "region": "local",
                    "zone": "zone-a"
                "address": {
                        "address": "10.244.0.8",
                    "region": "local",
                    "zone": "zone-b"
```

The proxy sees two endpoints in two zones, although both pods run on the one node. The `istio-locality` label on `probe-zone-b` overrides the node's zone. **If every endpoint shows an empty locality, stop here.** The cause is missing node labels or a missing `istio-locality` label, not your `DestinationRule`.

## The client needs a locality too

The endpoints are only one side of the comparison. The client's proxy compares its **own** locality with the locality of each endpoint. "Prefer the same zone" only means something if the client pod has a zone itself. A client without a locality has nothing to compare with.

### Check the locality of `shuttle`

The `shuttle` pod has no `istio-locality` label, so it takes the node's locality. Look at its labels:

```sh
kubectl -n starfleet get pod -l app=shuttle -o jsonpath='{.items[0].metadata.labels}{"\n"}' \
  | tr ',' '\n' | grep -i topology
```

```text
"topology.kubernetes.io/region":"local"
"topology.kubernetes.io/zone":"zone-a"
```

The `shuttle` pod runs in `local/zone-a`. Seen from `shuttle`, `zone-a` is its own zone and `zone-b` is the other zone.

Now look at the probe pod in `zone-b`. It carries the node's topology labels too, but its `istio-locality` label takes priority:

```sh
kubectl -n starfleet get pod -l zone=b -o jsonpath='{.items[0].metadata.labels}{"\n"}' \
  | tr ',' '\n' | grep -iE 'locality|topology'
```

```text
"istio-locality":"local.zone-b"
"topology.kubernetes.io/region":"local"
"topology.kubernetes.io/zone":"zone-a"
```

The endpoint list above showed `zone-b` for this pod. When a pod has both labels, Istio uses the `istio-locality` label.

> [!TIP]
> Before you debug any locality setting, run the endpoint list from the client pod. If an endpoint is in the wrong zone, or in none, fix the labels first. No `DestinationRule` can make up for a missing locality.

You now know where an endpoint's locality comes from, how `istio-locality` overrides it for one pod, and how to read the locality that the client's proxy really uses. Every endpoint in your playground has a locality, and so does `shuttle`. The open question is what Istio does with these localities, and what you must configure before it prefers the client's own zone.

## Common pitfalls

> [!WARNING]
> - **Expecting locality to be set per pod.** It comes from the node's `topology.kubernetes.io` labels. `istio-locality` is the override for when those are missing or wrong.
> - **Putting `istio-locality` on the Deployment instead of the pod template.** Only labels on the pods count.
> - **Changing the label and expecting running pods to change.** Istio reads the locality when the pod starts. Roll out the Deployment again.
> - **Writing the label value with slashes.** Use dots: `local.zone-b`.
> - **Forgetting the client.** "Prefer the same zone" is measured from the locality of the pod that sends the request.

## Your mission: Fix An Endpoint In The Wrong Locality Lab

You can now read the locality of every endpoint from the node labels, the `istio-locality` label and the client's endpoint list. In the lab, one probe pod runs in the wrong zone, so the `DestinationRule` cannot keep requests in the client's zone, and you must find that pod and give it the correct locality.

The lab runs in its own cluster, so first pause your playground. Nothing in it is lost:

```sh
astrona stop ats-014-playground-040-04
```

Then start the lab:

```sh
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-040/module-04/labs/lab-02
```

The task is on the next page. Solve it on your own first. When you think you are done, send it for grading:

```sh
astrona submit -c sections/section-040/module-04/labs/lab-02
```

When the lab is done, remove it and start your playground again:

```sh
astrona destroy ats-014-lab-040-04-02
astrona start ats-014-playground-040-04
```
