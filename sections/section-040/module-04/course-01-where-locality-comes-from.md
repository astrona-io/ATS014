# Where Locality Comes From

Astronaut, every locality setting chooses between orbits, so the first question is where a ship's orbit comes from, and how to check that it has one. Get this wrong and every setting after it silently does nothing, with no error to warn you.

## Three labels, one order

Istio builds an endpoint's **locality** from three **node** labels:

| Label | Level | Example |
| --- | --- | --- |
| `topology.kubernetes.io/region` | region, the largest area | `us-east1` |
| `topology.kubernetes.io/zone` | zone inside a region | `us-east1-b` |
| `topology.istio.io/subzone` | subzone inside a zone, Istio only, optional | `rack-3` |

Managed Kubernetes clusters set the first two for you. The third exists because Istio wanted a third level for racks or cells.

Together they form one address, written with slashes:

```text
   us-east1 / us-east1-b / rack-3
   └─region─┘ └───zone───┘ └subzone┘

   with wildcards in configuration:
   us-east1/*             every zone in the region
   us-east1/us-east1-b/*  one zone, any subzone
```

**Every pod inherits the locality of the node it runs on.** In the normal case there is nothing to set per pod: a ship's orbit is simply where it was launched.

## The `istio-locality` override

When node labels are missing or wrong, for example on a bare-metal or local test cluster, a pod can declare its own locality with the **`istio-locality`** label on its pod template:

```yaml
template:
  metadata:
    labels:
      app: probe
      istio-locality: local.zone-b
```

Two details:

- **The separator is a dot, not a slash.** A Kubernetes label value cannot contain `/`, so the format is `region.zone.subzone`. `local.zone-b` means region `local`, zone `zone-b`.
- **It overrides the node's locality** for that pod, and only for that pod. Your playground uses it to put two probes on one node into two different orbits.

The label must sit on the **pod template**, not on the Deployment's own `metadata`, and it is read when the pod starts. Changing it means new pods, so restart the Deployment afterwards.

## Check the orbits before you configure anything

Do this first, every time. If endpoints have no locality, nothing in the next parts will work, and there is no error message to tell you why.

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

(Your node name will end in `playground-040-04-control-plane`.)

Now ask the shuttle's communications officer which locality each probe endpoint has:

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

Two endpoints, two orbits, although both pods run on the one node: the `istio-locality` label on `probe-zone-b` overrides what the node says. **If every endpoint shows an empty locality, stop here.** The cause is missing node labels or a missing `istio-locality` label, not your `DestinationRule`.

## The sender needs an orbit too

Locality routing compares the **sender's** locality with each endpoint's. "Prefer the nearby orbit" only means something if the sending ship has an orbit itself. A sender without one has nothing to be near.

### Check the shuttle's orbit

The shuttle has no `istio-locality` label, so it takes the node's orbit. Look at its labels:

```sh
kubectl -n starfleet get pod -l app=shuttle -o jsonpath='{.items[0].metadata.labels}{"\n"}' \
  | tr ',' '\n' | grep -i topology
```

```text
"topology.kubernetes.io/region":"local"
"topology.kubernetes.io/zone":"zone-a"
```

The shuttle flies in `local/zone-a`. That makes `zone-a` the nearby orbit from its point of view, and `zone-b` the far one.

Now the probe in `zone-b`. It carries the node's labels too, but its `istio-locality` label wins:

```sh
kubectl -n starfleet get pod -l zone=b -o jsonpath='{.items[0].metadata.labels}{"\n"}' \
  | tr ',' '\n' | grep -iE 'locality|topology'
```

```text
"istio-locality":"local.zone-b"
"topology.kubernetes.io/region":"local"
"topology.kubernetes.io/zone":"zone-a"
```

The endpoint dump above showed `zone-b` for this pod. When both are present, the `istio-locality` label is the one Istio uses.

> [!TIP]
> Before you debug any locality setting, run the endpoint dump from the sender. If an endpoint is in the wrong orbit, or in none, fix the labels first. No `DestinationRule` can make up for a missing locality.

## Common pitfalls

> [!WARNING]
> - **Expecting locality to be set per pod.** It comes from the node's `topology.kubernetes.io` labels. `istio-locality` is the override for when those are missing or wrong.
> - **Putting `istio-locality` on the Deployment instead of the pod template.** Only labels on the pods count.
> - **Changing the label and expecting running pods to change.** Locality is read when the pod starts. Restart the Deployment.
> - **Writing the label value with slashes.** Use dots: `local.zone-b`.
> - **Forgetting the sender.** "Prefer nearby" is measured from the sending ship's orbit.

> *Locality comes from node labels, `istio-locality` overrides it per pod, and an endpoint without a locality makes every setting in this module do nothing.*

## Your mission: Give Every Ship Its Orbit

You can now read every ship's orbit from the node labels, the `istio-locality` label and the sender's endpoint dump. Now prove it in a graded mission: one ship sits in the wrong orbit, so the flight plan cannot keep signals close, and you have to put it where it belongs.

The mission runs in its own training solar system, so first pause your playground. Nothing in it is lost:

```sh
astrona stop ats-014-playground-040-04
```

Then start the mission:

```sh
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-040/module-04/labs/lab-02
```

Read the task in [`question.md`](./labs/lab-02/question.md) and solve it on your own first. When you think you are done, send it for grading:

```sh
astrona submit -c sections/section-040/module-04/labs/lab-02
```

When the mission is done, remove it and wake your playground up again:

```sh
astrona destroy ats-014-lab-040-04-02
astrona start ats-014-playground-040-04
```
