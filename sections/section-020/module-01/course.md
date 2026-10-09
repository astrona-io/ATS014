# Shift Traffic With Weighted Routing

A header match sends one particular request to one particular version. Releasing a new version is a different problem. You do not want one user on the new version. You want a set **share of all requests** to go there, and you want to control that share. If the new version misbehaves, you can turn the share down again before most users notice.

This is **weighted routing**, and every canary release in Istio uses it. A **canary release** sends a small share of requests to a new version before all traffic moves to it. The Istio object is the `VirtualService`, the object that tells the sidecar proxies where to send requests for a host. The new part is one field, `weight`, which gives each destination its share of the requests.

The field is small, but a lot happens around it. The proxy makes the split at random for each request, so it is easy to measure wrong. A merge patch that changes the weights replaces a whole list instead of editing it. And many people mix up weights and replica counts, which do not affect each other.

## Learning objectives

After this module you can:

- Write a `VirtualService` route with several weighted destinations, and put `weight` on the correct field.
- Write weights that add up to 100, predict the split when they do not, and say when `weight` may be left out.
- Explain how the proxy applies a weight (one random pick for each request) and what that means for how many requests you count.
- Run a canary rollout as a series of weight changes, and roll it back in one apply.
- Combine a header match with a weighted split, and predict which requests the weights apply to.
- Explain why a merge patch on `spec.http` must restate the whole route list.
- Explain why traffic share and replica count are independent, and predict the split when they disagree.
- Read `weightedClusters` from `istioctl proxy-config routes` and match each entry to your YAML.

## Before you start

This module builds on the two Istio routing objects. It expects the following knowledge, and a playground that is running before the first hands-on step.

### What you should already know

- **How the mesh works.** Istio adds a **sidecar proxy** (Envoy) to every pod; all traffic in and out of the pod passes through it. **`istiod`**, Istio's control plane, sends configuration to every proxy. You can read that configuration with `istioctl proxy-config`.
- **The two routing objects.** A `DestinationRule` defines **subsets**: named groups of a Service's pods, selected by a label such as `version: v1`. A `VirtualService` sends requests to those subsets. Weighted routing adds nothing new to this pair. It only puts numbers on the destinations.

### What is in your playground

Your playground is one `kind` cluster with **Istio 1.30.5**, installed with Helm. Everything runs in one namespace, **`starfleet`**, which has sidecar injection switched on. It runs the Istio Bookinfo sample app with other names:

| Workload | What it does |
| --- | --- |
| `bridge` | Web frontend (`/productpage`) on port `9080`; it calls `cargo` and `scout` |
| `cargo` | Backend that returns item details |
| `scout` v1, v2, v3 | Backend in three versions: v1 shows no stars, v2 black stars, v3 red stars. This is the Service you split in this module |
| `navcom` | Backend that `scout` v2 and v3 call for the star rating |
| `shuttle` | Test client pod; you send every test request from here |
| `probe` v1, v2 | HTTP echo server on port `8000`, free for your own tests |

The **`scout` `DestinationRule`** is already applied, with the subsets `v1`, `v2` and `v3`. There is **no** `VirtualService` yet, so for now the Kubernetes Service spreads requests over all three versions.

The web paths built into the app keep their original names. A request to `scout` goes to `http://scout:9080/reviews/0`. Each response names the pod that sent it (`"podname": "scout-v3-..."`), and that is how you count a split.

You can also open the `bridge` page in your browser at `http://127.0.0.1:9080/productpage`. Refresh it during a split, and the stars change from one request to the next.

Start your playground now, and keep it running while you read the parts:

<!-- astrona:playground -->

### One helper to paste first

Paste this into each new terminal. It sends a number of requests from `shuttle` to `scout` (20 if you give no number) and counts which version answered. Extra `curl` options go after the number:

```sh
count_versions() { n=${1:-20}; [ $# -gt 0 ] && shift; for i in $(seq 1 $n); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s "$@" http://scout:9080/reviews/0 | grep -o 'scout-v[0-9]'
done | sort | uniq -c; }
```

Use it like this: `count_versions` for 20 requests, `count_versions 100` for 100, or `count_versions 10 -H "end-user: jason"` for 10 requests with the header `end-user: jason`.

## The order of the parts

The module has three parts, a lab after the first part, a lab after the third part, and a summary at the end.

The first part writes a route with several weighted destinations. It shows where `weight` goes, how the proxy uses it, and what happens when the weights do not add up to 100, when a weight is 0, or when a weight points at a subset that does not exist. Its lab asks you to split the `scout` requests three ways.

The second part runs a canary rollout: it moves the weights forward step by step, rolls them back in one apply, changes them with a merge patch, and keeps one user out of the split with a header rule. The third part shows that traffic share does not follow the replica count, and reads the weights out of a live proxy. Its lab asks you to run a canary with a header rule above the split, without changing any replica count.
