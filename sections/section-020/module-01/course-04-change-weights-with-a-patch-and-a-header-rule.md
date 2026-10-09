# Change Weights With A Patch And A Header Rule

A canary release moves users to a new version a little at a time, by applying the same weighted route again with new numbers. Two everyday tasks come up during such a rollout. Scripts often change the weights with `kubectl patch` instead of a full file, and testers often need the new version for every request while everyone else stays in the split. This part shows how to do both without breaking the route.

A `VirtualService` is the Istio object that tells the sidecar proxies where to send requests for a host. Its `http` field is a list of rules, and each rule has a route with one or more destinations and their `weight`: each destination's share of the requests. The **sidecar proxy** is the Envoy proxy that Istio adds to every pod, and the proxy of the sending pod makes one random pick for each request, with the weights as the odds. So count at least 100 requests before you judge a split.

The commands below also need the `scout` `DestinationRule` applied in your playground. A `DestinationRule` defines **subsets**: named groups of a Service's pods, selected by a label. Here the subsets `v1`, `v2` and `v3` select the `scout` pods by their `version` label.

## Changing weights with a patch

`kubectl apply` with the complete object is the safest way to change the numbers. Rollout scripts often use a merge patch instead, so you should be able to read one. A **merge patch** (`kubectl patch --type merge`) changes only the fields you write. But it **replaces a list as one piece**. It cannot edit one item of a list, because it has no key to match the items. So a patch on `spec.http` must restate the **whole** list, including the parts that did not change.

A patch changes an object that already exists, so the commands below need a `scout` `VirtualService` in your playground. Any version of it works, because the patch replaces its whole `http` list.

<!-- astrona:playground:renew -->

The commands in this part use a small helper. It sends a number of requests from the `shuttle` pod to `scout` (20 if you give no number) and counts which version answered. Extra `curl` options go after the number. Paste it into your terminal if it is not there yet:

```sh
count_versions() { n=${1:-20}; [ $# -gt 0 ] && shift; for i in $(seq 1 $n); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s "$@" http://scout:9080/reviews/0 | grep -o 'scout-v[0-9]'
done | sort | uniq -c; }
```

If your playground has no `scout` `VirtualService` yet, create one that sends every request to v1. Save this as `virtualservice-scout-v1.yaml`:

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

Now patch it. This patch sets the split to 90/10:

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

A patch changes the numbers. A second rule changes which requests the numbers apply to. The `http` rules of a `VirtualService` are still checked from the top, and the first one that matches wins. So a header match placed **above** the weighted rule takes those requests out of the split completely. This is a common real rollout: your testers always use the newest version, while a small share of everyone else tries the next one.

The example below uses the request header `end-user`, which the `bridge` frontend adds after a user logs in. Here the user jason, whose requests carry `end-user: jason`, always goes to v3, and everyone else is split 90/10 between v1 and v2. Save this as `virtualservice-scout.yaml`:

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

You now know how to read and write a merge patch on `spec.http`, and why it must restate the whole list. You can also keep testers out of the split with a header rule above the weighted one, and measure the right group of requests. One question is still open: what happens to the split when the versions run different numbers of pods?

## Common pitfalls

> [!WARNING]
> - **Expecting a merge patch to edit one route item.** It replaces the whole `http` list. Restate it, or use `kubectl apply` with the complete object.
> - **Patching a `VirtualService` that does not exist.** `kubectl patch` changes an existing object only. Apply the object first.
> - **Forgetting a match rule above the weighted one.** Those requests never enter the split, so you measure a different group than you think.
> - **Adding weights across rules.** Weights add up to 100 inside one route list. There is no shared total across `http` rules.
