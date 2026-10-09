# Run A Canary Rollout And Roll It Back

A **canary release** moves users to a new version a little at a time. First a small share of requests goes to the new version. If it works well, the share grows until all traffic uses it. If it does not, every request goes back to the old version in one step.

Istio has no special feature for this. A canary is the same weighted `VirtualService` (the Istio object that tells the sidecar proxies where to send requests for a host), applied a few times with new numbers. This part is about doing that safely: how to measure a split, how to move forward and back, how to change weights with a patch, and how to keep your testers out of the split.

The commands below need the `scout` `DestinationRule` applied in your playground. It defines the subsets `v1`, `v2` and `v3`, which select the `scout` pods by their `version` label.

## Measuring a random split

The sidecar proxy of the sending pod makes a separate random pick for each request, so a small sample tells you almost nothing. At a true 80/20 split, ten requests that all go to v1 are normal: it happens about one time in ten. A common mistake is to decide from such a sample that the weights are broken, and then "fix" a `VirtualService` that was correct.

This table is a rough guide for reading your own counts:

| Requests counted | What you can conclude at a set 80/20 |
| --- | --- |
| 10 | almost nothing; 10/0 and 6/4 are both normal |
| 100 | the split is in the right area; expect roughly 75–85 |
| 1000 | close to the weight, within a percent or two |

Use 100 requests as your working minimum, and expect a few percent of difference even then. When a task says "confirm the split", it means over enough requests to mean something.

## Moving the rollout forward

With a way to measure in place, you can move the rollout forward. Each step of the rollout is the **same** `VirtualService`, `scout`, with new numbers. The name and namespace stay the same, so every `kubectl apply` replaces the split before it. You never delete anything between steps.

<!-- astrona:playground:renew -->

The commands in this part use a small helper. It sends a number of requests from the `shuttle` pod to `scout` (20 if you give no number) and counts which version answered. Extra `curl` options go after the number. Paste it into your terminal if it is not there yet:

```sh
count_versions() { n=${1:-20}; [ $# -gt 0 ] && shift; for i in $(seq 1 $n); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s "$@" http://scout:9080/reviews/0 | grep -o 'scout-v[0-9]'
done | sort | uniq -c; }
```

Start by moving from an 80/20 split to 50/50. Save this as `virtualservice-scout-50-50.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: scout
  namespace: starfleet
spec:
  hosts:
  - scout
  http:
  - route:
    - destination:
        host: scout
        subset: v1
      weight: 50
    - destination:
        host: scout
        subset: v3
      weight: 50
```

Apply it:

```sh
kubectl apply -f virtualservice-scout-50-50.yaml
```

Then check the result. Count 20 requests:

```sh
count_versions
```

You should see something like:

```text
   8 scout-v1
  12 scout-v3
```

Roughly half of the requests go to each version. You changed two numbers, and no pod was scaled or restarted.

The last step of the rollout sends every request to v3. It has one destination, so it needs no `weight`. Save this as `virtualservice-scout-v3.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: scout
  namespace: starfleet
spec:
  hosts:
  - scout
  http:
  - route:
    - destination:
        host: scout
        subset: v3
```

Apply it:

```sh
kubectl apply -f virtualservice-scout-v3.yaml
```

Then check the result:

```sh
count_versions
```

You should see:

```text
  20 scout-v3
```

All `scout` traffic now goes to the new version.

## Rolling back

A weight change takes effect as fast as `istiod`, Istio's control plane, can push it to the proxies: a second or two on a small cluster. `istiod` sends the new configuration to every running proxy over **xDS**, the protocol it uses to update proxies while they run. No pod restarts and no Deployment changes, so the application does not notice anything.

So the speed that matters is not how fast you can move requests *to* a new version. It is how fast you can move them *away* from it:

```mermaid
flowchart LR
    A["100 / 0"] --> B["80 / 20"]
    B --> C["50 / 50"]
    C --> D["0 / 100"]
    D -->|"one apply"| A
```

The diagram shows the weights for v1 and v3 at each step of a rollout, and a rollback that goes from the last step straight back to the first in one apply.

Forward is a rollout and backward is a rollback. Both are the same operation with different numbers, and no step recreates a pod. A rollback needs no special procedure: it is the old numbers, applied again. A Deployment rollback, by comparison, recreates pods and takes as long as their readiness checks allow.

To roll back, save this as `virtualservice-scout-v1.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: scout
  namespace: starfleet
spec:
  hosts:
  - scout
  http:
  - route:
    - destination:
        host: scout
        subset: v1
```

Apply it:

```sh
kubectl apply -f virtualservice-scout-v1.yaml
```

Then check the result:

```sh
count_versions
```

You should see:

```text
  20 scout-v1
```

One apply undid the whole rollout, within seconds.

## Changing weights with a patch

`kubectl apply` with the complete object is the safest way to change the numbers. Rollout scripts often use a merge patch instead, so you should be able to read one. A **merge patch** (`kubectl patch --type merge`) changes only the fields you write. But it **replaces a list as one piece**. It cannot edit one item of a list, because it has no key to match the items. So a patch on `spec.http` must restate the **whole** list, including the parts that did not change.

This patch sets the split to 90/10:

```sh
kubectl -n starfleet patch virtualservice scout --type merge -p '
spec:
  http:
    - route:
        - destination:
            host: scout
            subset: v1
          weight: 90
        - destination:
            host: scout
            subset: v3
          weight: 10'
```

```text
virtualservice.networking.istio.io/scout patched
```

Then check the result. Count 100 requests:

```sh
count_versions 100
```

You should see something like:

```text
  85 scout-v1
  15 scout-v3
```

The patch replaced the whole `http` list with the one you wrote, and the split is near 90/10. If your `VirtualService` had a second rule, that rule would now be gone. The rule for any list field is the same: restate the whole list, or use `kubectl apply` with the complete object.

## A rule above the weights changes who is counted

The `http` rules of a `VirtualService` are still checked from the top, and the first one that matches wins. So a header match placed **above** the weighted rule takes those requests out of the split completely. This is a common real rollout: your testers always use the newest version, while a small share of everyone else tries the next one.

Here the user jason always goes to v3, and everyone else is split 90/10 between v1 and v2. Save this as `virtualservice-scout.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: scout
  namespace: starfleet
spec:
  hosts:
  - scout
  http:
  - match:
    - headers:
        end-user:
          exact: jason
    route:
    - destination:
        host: scout
        subset: v3
  - route:
    - destination:
        host: scout
        subset: v1
      weight: 90
    - destination:
        host: scout
        subset: v2
      weight: 10
```

Apply it:

```sh
kubectl apply -f virtualservice-scout.yaml
```

Then check the result. Send 5 requests with the header `end-user: jason`, and 100 without it:

```sh
count_versions 5 -H "end-user: jason"
count_versions 100
```

You should see something like:

```text
   5 scout-v3
  89 scout-v1
  11 scout-v2
```

jason's requests never enter the split. The first rule matches them, so the weights never apply to them. All other requests fall through to the second rule and divide roughly 90/10.

The weights add up to 100 **inside their own route list**. The proxy handles each `http` rule on its own; there is no shared total across rules.

> [!TIP]
> When a measured split does not match your weights, read the whole `http` list first. A rule above the weighted one may be taking some requests out of the group you are counting.

You now know how to measure a split honestly, move a rollout forward and back with one apply each, read a merge patch on `spec.http`, and keep testers out of the split with a header rule above it. One question is still open: what happens to the split when the versions run different numbers of pods?

## Common pitfalls

> [!WARNING]
> - **Deciding anything from ten requests.** At a true 80/20, ten requests that land 10/0 happen about one time in ten. Count 100 before you trust a number.
> - **Deleting the `VirtualService` between rollout steps.** You do not need to. The same name in the same namespace means `kubectl apply` replaces it.
> - **Expecting a merge patch to edit one route item.** It replaces the whole `http` list. Restate it, or use `kubectl apply` with the complete object.
> - **Forgetting a match rule above the weighted one.** Those requests never enter the split, so you measure a different group than you think.
> - **Treating a rollback as a separate procedure.** It is the old numbers, applied again.
