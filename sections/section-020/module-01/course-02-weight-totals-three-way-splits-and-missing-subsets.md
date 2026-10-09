# Weight Totals, Three-Way Splits And Missing Subsets

A weighted route is easy to write when the numbers are 80 and 20. Real tasks are less tidy. Weights may not add up to 100, a route may list three versions, a version may need to wait at zero, or a weight may point at a subset that does not exist. This part shows what Istio does in each of these cases, so you can predict the split before you measure it.

A `VirtualService` is the Istio object that tells the sidecar proxies where to send requests for a host. A weighted route in it lists several destinations and gives each one a `weight`: its share of the requests. The commands below also need the `scout` `DestinationRule` applied in your playground. A `DestinationRule` is the Istio object that defines **subsets**: named groups of a Service's pods, selected by a label. Here the subsets `v1`, `v2` and `v3` select the `scout` pods by their `version` label.

The **sidecar proxy** is the Envoy proxy that Istio adds to every pod; all traffic in and out of the pod passes through it. **`istiod`**, Istio's control plane, turns each route into proxy configuration. For every request, the sidecar proxy of the sending pod makes one random pick between the destinations, with the weights as the odds. Every case below follows from that one pick.

## Weights that do not add up to 100

What happens if you write 50 and 30, which add up to 80? On Istio 1.30.5 the `VirtualService` is accepted with no error and no warning. The proxy uses the weights as **relative** shares: v1 gets 50 out of 80 (62.5%) and v3 gets 30 out of 80 (37.5%). It does **not** mean "50% to v1, 30% to v3, 20% to nowhere".

<!-- astrona:playground:renew -->

The commands in this part use a small helper. It sends a number of requests from the `shuttle` pod to `scout` (20 if you give no number) and counts which version answered. Paste it into your terminal if it is not there yet:

```sh
count_versions() { n=${1:-20}; [ $# -gt 0 ] && shift; for i in $(seq 1 $n); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s "$@" http://scout:9080/reviews/0 | grep -o 'scout-v[0-9]'
done | sort | uniq -c; }
```

Save this as `virtualservice-scout.yaml`, replacing the old file if you have one:

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
      weight: 30
```

Apply it:

```sh
kubectl apply -f virtualservice-scout.yaml
```

Then check the result. Count 100 requests, run `istioctl analyze` (the `istioctl` command that checks your Istio objects for known problems), and print the weights that the `shuttle` proxy received:

```sh
count_versions 100
istioctl analyze -n starfleet
istioctl proxy-config routes deploy/shuttle -n starfleet --name 9080 -o json | grep '"weight"'
```

You should see something like:

```text
  63 scout-v1
  37 scout-v3
✔ No validation issues found when analyzing namespace: starfleet.
                                        "weight": 50
                                        "weight": 30
```

The split is about 62/38, and no tool complains. The proxy received the raw numbers, 50 and 30, and uses them as a ratio. Still write weights that add up to 100. That is what a task means, and older Istio versions rejected any other total.

## More than two destinations

With the total settled, the next case is the number of destinations. A route can share requests between any number of them. The proxy makes a new pick for each request, so the more requests you count, the closer you get to the split you set.

To send 50% to v1, 25% to v2 and 25% to v3, save this as `virtualservice-scout.yaml`, replacing the old file:

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
        subset: v2
      weight: 25
    - destination:
        host: scout
        subset: v3
      weight: 25
```

Apply it:

```sh
kubectl apply -f virtualservice-scout.yaml
```

Then check the result. Count 40 requests, and then 100:

```sh
count_versions 40
count_versions 100
```

You should see something like:

```text
  23 scout-v1
  11 scout-v2
   6 scout-v3
  50 scout-v1
  21 scout-v2
  29 scout-v3
```

With 40 requests, v3 got only 6 instead of about 10. With 100, all three versions are close to 50/25/25. Small counts move around a lot.

## `weight: 0` keeps a destination ready

A three-way split is one way to list several versions. Sometimes you want a version listed but not yet used. A destination with `weight: 0` is allowed, and it gets no requests. It keeps the destination **in your YAML**. Moving a rollout forward is then a change to one number, not a new block of YAML that you must indent correctly under time pressure.

Save this as `virtualservice-scout.yaml`, replacing the old file:

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
      weight: 100
    - destination:
        host: scout
        subset: v3
      weight: 0
```

Apply it:

```sh
kubectl apply -f virtualservice-scout.yaml
```

Then check the result. Count, and print the clusters in the `shuttle` proxy's route. A **cluster** is Envoy's name for one destination it can send requests to, and each subset becomes its own cluster:

```sh
count_versions
istioctl proxy-config routes deploy/shuttle -n starfleet --name 9080 -o json | grep -B1 '"weight"' | grep -E 'name|weight'
```

You should see:

```text
  20 scout-v1
                                        "name": "outbound|9080|v1|scout.starfleet.svc.cluster.local",
                                        "weight": 100
```

Every request goes to v1. The proxy's route does not even list v3: `istiod` leaves a destination with weight 0 out of the configuration it sends. The destination only lives in your YAML, ready for the next step.

## A weight on a subset that does not exist

A zero weight is a safe mistake to make. A weight on the wrong subset is not. No check stops you from giving a weight to a subset that the `DestinationRule` never defined. Kubernetes accepts the `VirtualService`, and the requests sent to that subset fail.

To see this, change your file so the second destination is `subset: v9` with `weight: 50`, and v1 has `weight: 50`. Save it as `virtualservice-scout.yaml`:

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
        subset: v9
      weight: 50
```

Apply it:

```sh
kubectl apply -f virtualservice-scout.yaml
```

Then check the result. Send six requests and print only the HTTP status code of each, then run `istioctl analyze`:

```sh
for i in 1 2 3 4 5 6; do kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code} " http://scout:9080/reviews/0; done; echo
istioctl analyze -n starfleet
```

You should see something like this (the `analyze` output is shortened to the error):

```text
503 200 503 503 200 200
Error [IST0101] (VirtualService starfleet/scout) Referenced host+subset in destinationrule not found: "scout+v9"
```

About half the requests fail with `503 Service Unavailable`: those are the ones the random pick sent to `v9`. `istioctl analyze` names the problem with the message code `IST0101`, which means the object refers to something that does not exist.

> [!TIP]
> Run `istioctl analyze` after every weight change. It is the only check that notices a weight on a subset that does not exist.

## What a weight is not

Two more facts prevent a whole group of mistakes. First, a weight is not a rate limit. It divides the requests that arrive; it does not cap them. At `weight: 20`, if ten times more requests arrive, v3 gets ten times more requests than before.

Second, a weight does not keep one user on one version. Two requests in a row from the same client can go to different subsets, because each pick is separate. If a user must stay on one version, use a header match instead.

You now know what happens with weights that do not add up to 100, with three destinations, with `weight: 0`, and with a subset that does not exist. You can also prove each case with a count and with the proxy's own route. The open question is how to change these weights safely while real users depend on the service.

## Common pitfalls

> [!WARNING]
> - **Writing weights that do not add up to 100.** Istio 1.30.5 accepts them and uses them as a ratio, so 50 + 30 gives about 62/38, not 50/30.
> - **Judging a three-way split from a small count.** With 40 requests, one version can be far off its share. Count 100 or more.
> - **Expecting a `weight: 0` destination in the proxy's route.** `istiod` leaves it out; it only stays in your YAML.
> - **Giving a weight to a subset that no `DestinationRule` defines.** Nothing rejects it, and those requests fail with `503`. Run `istioctl analyze`.
> - **Reading a weight as a rate limit.** It divides the requests that arrive. It does not cap them.

## Your mission: Split Traffic Three Ways With Weights Lab

You can now write a weighted route, predict the split, and measure it over enough requests. The lab asks you to change an existing `VirtualService` so that `scout` requests split between three versions in exact shares, and to prove the split with live requests.

The lab runs in its own cluster, so first pause your playground. Nothing in it is lost:

```sh
astrona stop ats-014-playground-020-01
```

Then start the lab:

```sh
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-020/module-01/labs/lab-02
```

The task is on the next page. Solve it on your own first. When you think you are done, send it for grading:

```sh
astrona submit -c sections/section-020/module-01/labs/lab-02
```

When the lab is done, remove it and start your playground again:

```sh
astrona destroy ats-014-lab-020-01-02
astrona start ats-014-playground-020-01
```
