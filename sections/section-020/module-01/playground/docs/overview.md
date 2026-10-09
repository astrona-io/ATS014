# Overview: Shift Traffic With Weighted Routing (Playground)

This is a **playground**, not a lab. It starts a cluster, installs Istio and the example app, and then waits for you. There is no task, no `astrona submit`, and no pass or fail. Try things, break things, run `astrona destroy`, and start over.

## What's in the box

- A single-node `kind` Kubernetes cluster. `astrona run` points `kubectl` at it (context `kind-astro-ats-014-playground-020-01`).
- **Istio 1.30.5**, installed with Helm: `istio-base` (the custom resource definitions) and `istiod` (Istio's control plane, which sends configuration to every proxy). There is no ingress or egress gateway. You need `istioctl` on your own machine for the `istioctl` commands.
- The namespace **`starfleet`**, labelled `istio-injection=enabled`, so every pod gets a sidecar proxy (Envoy), a proxy container that handles all traffic in and out of the pod. It runs the Istio Bookinfo sample app with other names:
  - `bridge`, the web frontend; `cargo`, a backend that returns item details; `navcom`, a backend that returns the star rating; and `scout` in three versions. `scout-v1` shows no stars, `v2` black stars and `v3` red stars.
  - `shuttle`, a client pod inside the mesh. You send test requests from it.
  - `probe` v1 and v2 on port `8000`, an HTTP echo server you can use freely.
- Access logs are on for the whole mesh, so each sidecar proxy writes one line per request.
- The **`scout` `DestinationRule`** is already applied, with the subsets `v1`, `v2` and `v3`. A subset is a named group of a Service's pods, selected by a label; here, by the `version` label.
- **No `VirtualService`.** Writing the weighted `VirtualService` is the point of the module, so for now the Kubernetes Service spreads requests over all three versions.
- The `bridge` page at `http://127.0.0.1:9080/productpage`. Refresh it during a split, and the stars change from one request to the next.

Every pod shows `2/2`: the application container plus its `istio-proxy` sidecar container.

## The helper used in this module

Paste this once in each new terminal. It sends a number of requests (20 if you give no number) from `shuttle` to `scout` and counts which version answered. The `scout` answers on the path `/reviews/0`. The path is built into the app, so it keeps its original name. The response contains `"podname": "scout-vX-..."`, which is how the helper tells the versions apart. Extra `curl` options go after the number:

```sh
count_versions() { n=${1:-20}; [ $# -gt 0 ] && shift; for i in $(seq 1 $n); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s "$@" http://scout:9080/reviews/0 | grep -o 'scout-v[0-9]'
done | sort | uniq -c; }
# count_versions 40                        40 requests
# count_versions 10 -H "end-user: jason"   10 requests as jason
```

## Things to try

Each idea is a small change to a `VirtualService` you write yourself. Save the YAML to a file, apply it with `kubectl apply -f`, and count.

- Count 20 requests before you write anything. All three versions answer, because the Kubernetes Service picks pods, not versions.
- Apply an 80/20 split between v1 and v3, and count 20 requests, then 100. See how much the small sample moves around.
- Move the rollout forward (80/20, 50/50, then all to v3) and then roll it back with one apply. No pod restarts at any step.
- Scale `scout-v1` to 4 replicas at a 50/50 split. The share stays 50/50.
- Apply weights of 50 and 30, which add up to 80, and work out the share each version gets.
- Send jason to v3 with a header rule above a 90/10 split, and check that jason's requests never enter the split.
- Give a weight to a subset called `v9`, and run `istioctl analyze`.

## Start over without a new cluster

```sh
kubectl delete virtualservice --all -n starfleet
```

The `scout` `DestinationRule` stays, so you are back at the starting state.

## When you're done

```sh
astrona destroy ats-014-playground-020-01
```

`astrona destroy` takes the environment name, not the configuration path.

## Practice tasks

This is an exam-style task. It uses the `count_versions` helper from the top of this page. Try it on your own first, then open the solution. The solution was run and checked on a cluster like this one.

> Send **10%** of `scout` requests to **v2** and the rest to **v1**. Check it with 40 requests, then with 100.

<details><summary>Solution</summary>

Save this as `virtualservice-scout.yaml`:

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

Then check the result. Count 40 requests, and then 100:

```sh
count_versions 40
count_versions 100
```

You should see something like:

```text
  36 scout-v1
   4 scout-v2
  93 scout-v1
   7 scout-v2
```

With 40 requests you expect about 4 on v2, and with 100 about 10. The sidecar proxy makes a separate random pick for each request, so your numbers will be a little above or below those values.

</details>
