# Overview: Fault Injection With Delays And Aborts (Playground)

> Declared in [`../config.yaml`](../config.yaml) under `metadata.docs.guide`.

This is a **playground**, not a lab. It starts, installs Istio and the Bookinfo
app, and then waits. There is no task, no `astrona submit`, and no pass/fail.
Explore, break things, `astrona destroy`, start over.

Welcome, astronaut. Fault injection is a simulation drill. You fake a delay or a
failure on purpose, so you can watch how the crew copes before a real emergency
happens. This playground is your training solar system in the simulator.

## What's in the box

- A single-node `kind` cluster. `kubectl` is already pointed at it
  (context `kind-astro-ats-014-playground-050-01`).
- **Istio 1.30.5**, installed with Helm: `istio-base` and `istiod` only. There
  is no ingress or egress gateway, because this module does not need one.
- Access logs turned on for the whole mesh, so every sidecar writes one line
  per request.
- Namespace **`bookinfo`**, labelled for sidecar injection, with:
  - **Bookinfo**: `productpage`, `details`, `reviews` v1, v2 and v3, and
    `ratings` v1, all on port `9080`. `reviews` v2 and v3 call `ratings`;
    `reviews` v1 does not.
  - **`curl`**: a client pod inside the mesh. You send test requests from it.
  - **`httpbin`** v1 and v2 on port `8000`. Not used in this module.
- DestinationRules that define the subsets `reviews` v1/v2/v3 and `ratings` v1.
- **No `VirtualService`.** Writing them is the point of the module.
- The Bookinfo page at <http://127.0.0.1:9080/productpage>. Log in as `jason`
  to see faults on the page itself.

Every pod shows `2/2`: the app plus its `istio-proxy` sidecar.

## Helper functions

Paste these once into each new terminal. The module's "Try it" steps use them.

```sh
# status code + time of one request
status_and_time() { kubectl exec -n bookinfo deploy/curl -- curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" "$@"; }
# 10 requests to ratings, counted by status code
count_ratings_status() { for i in $(seq 1 10); do
  kubectl exec -n bookinfo deploy/curl -- curl -s -o /dev/null -w "%{http_code}\n" http://ratings:9080/ratings/0
done | sort | uniq -c; }
```

## The YAML files

The [`examples/`](../examples/) folder holds every manifest the module uses,
numbered and commented. The commands below use paths like
`examples/cases/c1-...yaml`, so run them from this `playground/` folder in a
clone of the repository. The course pages write each manifest to a file first,
so you can follow them without a clone.

| File | What it does |
| --- | --- |
| `01-virtualservice-ratings-abort-50.yaml` | 50% of requests to `ratings` get HTTP 500 |
| `02-virtualservice-ratings-abort-jason.yaml` | HTTP 500 for `end-user: jason` only |
| `03-virtualservice-ratings-delay-and-abort.yaml` | 50% delayed by 1s and 20% aborted with 503, on one rule |
| `04-virtualservice-reviews-jason-v2.yaml` | `jason` to `reviews` v2 (which calls `ratings`), everyone else to v1 |
| `05-virtualservice-ratings-delay-2s.yaml` | Every call to `ratings` waits 2s |
| `06-virtualservice-reviews-timeout.yaml` | Everyone to `reviews` v2, with a 0.5s timeout |

## Cases to try

Each case is one file in [`examples/cases/`](../examples/cases/). Apply it, run
the test, and compare with the expected result. The results shown were taken
on this environment; percentages are random, so your counts will differ.

**Case 1 – `ratings` completely down.** A 100% abort with 503.

```bash
kubectl apply -f examples/cases/c1-virtualservice-ratings-abort-503-all.yaml
status_and_time http://ratings:9080/ratings/0
# 503 0.003s     ← instant: no network call
```

The answer comes back in milliseconds, because the caller's sidecar answers by
itself.

**Case 2 – rarely slow.** 10% of requests get a 1s delay.

```bash
kubectl apply -f examples/cases/c2-virtualservice-ratings-delay-10-percent.yaml
for i in $(seq 1 30); do
  kubectl exec -n bookinfo deploy/curl -- curl -s -o /dev/null -w "%{time_total}\n" http://ratings:9080/ratings/0 \
    | awk '{print ($1 > 0.9 ? "slow" : "fast")}'
done | sort | uniq -c
#  29 fast
#   1 slow       (about 3 expected – random)
```

**Case 3 – a fault for one calling service.** `sourceLabels` matches the labels
of the pod that *sends* the request.

```bash
kubectl apply -f examples/04-virtualservice-reviews-jason-v2.yaml
kubectl apply -f examples/cases/c3-virtualservice-ratings-abort-from-reviews-only.yaml
status_and_time http://ratings:9080/ratings/0
# 200            ← curl calls ratings directly: not affected
kubectl exec -n bookinfo deploy/curl -- curl -s -H "end-user: jason" http://reviews:9080/reviews/0 \
  | grep -o '"rating": {[^}]*}' | head -1
# "rating": {"error": "Ratings service is currently unavailable"}   ← via reviews: fails
```

**Case 4 – can retries hide the fault?** No. A route with `fault` ignores its
own `retries`.

```bash
kubectl apply -f examples/cases/c4-virtualservice-ratings-abort-with-retries.yaml
count_ratings_status
#   3 200
#   7 500        ← still about half, retries did nothing
```

**Case 5 – delay and timeout on the same route.** A route with `fault` also
ignores its own `timeout`.

```bash
kubectl apply -f examples/cases/c5-virtualservice-ratings-delay-and-timeout.yaml
status_and_time http://ratings:9080/ratings/0
# 200 2.0s   ← NOT 504 after 0.5s
```

Put the delay on the service being called and the timeout on the caller, as
[Part 3](../../course-03-scoping-composition-and-hazards.md) shows.

## Practice

An exam-style task with a checked solution: [practice.md](practice.md).

## Start over

To remove every rule without building a new cluster:

```bash
kubectl delete virtualservice --all -n bookinfo
```

The subsets stay in place, because the playground installed them.

## When you're done

```sh
astrona destroy ats-014-playground-050-01
```

(`astrona destroy` takes the environment name, not the configuration path.)
