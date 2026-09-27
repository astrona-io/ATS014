# Part 1 — Subsets And The Destination Vocabulary

> Prerequisite: [the module landing page](./course.md). Next: [Part 2 — Matching A Request](./course-02-matching-a-request.md).

Before Istio can send a request to "v2", something has to define what `v2` means. That is the `DestinationRule`'s entire job in this module, and it is worth its own part because of a property that surprises everyone the first time: applying a correct `DestinationRule` changes no traffic whatsoever. It creates vocabulary. This part settles what that vocabulary is made of, what the control plane builds out of it, and why a subset that matches nothing is not an error.

## What the Service already does

Start from the state the playground hands you. The `notification-service` Service selects on `app: notification-service` and nothing else, so both the `v1` pod and the `v2` pod are endpoints of it. Kubernetes has no further opinion, and neither — yet — does Istio.

> [!TIP]
> **Try it — the unconfigured baseline**
>
> ```sh
> kubectl -n routing-demo exec deploy/tester -- sh -c \
>   'for i in $(seq 1 20); do curl -s -X POST http://notification-service/notify; echo; done' | sort | uniq -c
> ```
>
> Expect something like:
>
> ```text
>   11 ["EMAIL"]
>    9 ["EMAIL","SMS"]
> ```
>
> The exact split varies run to run. `["EMAIL"]` is v1 and `["EMAIL","SMS"]` is v2 — two different answers from one Service name, with nothing you can do about which you get. That is the problem the module solves.

## From Service to cluster: what the control plane builds

The mechanism underneath is worth seeing once, because every `proxy-config` command in this course reads one stage of it.

`istiod` watches Kubernetes and turns the service registry into Envoy configuration, which it pushes to every sidecar over **xDS** — Envoy's configuration APIs, named per resource type (CDS for clusters, EDS for endpoints, LDS for listeners, RDS for routes). The pipeline for one Service:

```text
 Kubernetes                    istiod                         Envoy sidecar
 ──────────                    ──────                         ─────────────
 Service                  ┌─ builds one CLUSTER per      ┌─ CDS: named destinations
 notification-service ───►│  (host, port, subset)   ────►│   outbound|80||notification-service...
   selector: app=…        │                              │   outbound|80|v1|notification-service...
                          │                              │   outbound|80|v2|notification-service...
 EndpointSlice            └─ builds the ENDPOINT list    └─ EDS: pod IPs per cluster
   10.244.0.11 (v1)          per cluster, filtered by        cluster …|v1|… → 10.244.0.11
   10.244.0.12 (v2)          the subset's labels             cluster …|v2|… → 10.244.0.12
```

A **cluster**, in Envoy's vocabulary, is a named destination the proxy can send traffic to. Without any `DestinationRule` there is exactly one cluster for the Service, holding every ready endpoint. A `DestinationRule` with two subsets makes `istiod` build two *additional* clusters — same host, same port, different endpoint filters.

The cluster name is structured, and reading it is a skill you will use in every later module:

```text
outbound | 80 | v2 | notification-service.routing-demo.svc.cluster.local
   │       │    │     └── the fully qualified host
   │       │    └──────── the subset name — EMPTY for "no subset"
   │       └───────────── the port
   └───────────────────── direction: outbound (client side) or inbound (server side)
```

`outbound|80||notification-service…` with nothing between the middle pipes is the subset-less cluster. That empty field is not a typo in the output; it is the absence of a subset.

## The `DestinationRule` object

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: notification-service
  namespace: routing-demo
spec:
  host: notification-service
  subsets:
    - name: v1
      labels:
        version: v1
    - name: v2
      labels:
        version: v2
```

Read it as: *for the host `notification-service`, the word `v1` means the endpoints labelled `version: v1`.*

Three properties follow from the pipeline above:

- **The subset name is arbitrary.** `v1` and `v2` are convention. `stable`, `canary` and `blue` are equally valid; the name is a label for a cluster, not a reference to anything in Kubernetes.
- **The labels select over pods, not over Services.** They are matched against pod labels, which is why the pods in this playground carry a `version` label that the Service selector deliberately ignores.
- **A subset with no matching pods is not an error.** It produces a valid cluster with zero endpoints. Nothing rejects it, nothing warns; requests routed there fail at request time with 503. Istio validates that your YAML is well-formed, not that your labels match reality.

The general rule: **a `DestinationRule` is client-side policy for one host.** Subsets are the part this module uses, but the same object is where load balancer settings, connection pool limits and outlier detection go in later sections — all of them decisions the *calling* proxy makes about a destination.

> [!TIP]
> **Try it — confirm the labels a subset will select on**
>
> ```sh
> kubectl -n routing-demo get pods --show-labels
> ```
>
> Expect something like:
>
> ```text
> NAME                                       READY   STATUS    AGE   LABELS
> notification-service-v1-7d4c9b6f8d-x2mkq   2/2     Running   4m    app=notification-service,version=v1,...
> notification-service-v2-6f8b7c5d94-lq7rn   2/2     Running   4m    app=notification-service,version=v2,...
> tester-5c7d8f9b6c-8vzpl                    2/2     Running   4m    app=tester,...
> ```
>
> The `version=v1` / `version=v2` labels are what a subset selects on. `2/2` confirms each pod runs its application container plus the injected `istio-proxy` — the proxy that will hold the clusters you are about to create.

## Watching the clusters appear

Because the pipeline is observable, you can apply the `DestinationRule` and see exactly what it produced without sending a single request. This is the cleanest demonstration in the module that subsets are vocabulary rather than behaviour: the cluster list grows, and the traffic split does not move.

> [!TIP]
> **Try it — two new clusters, zero change in behaviour**
>
> ```sh
> istioctl proxy-config cluster deploy/tester -n routing-demo | grep notification
> kubectl apply -f - <<'EOF'
> apiVersion: networking.istio.io/v1
> kind: DestinationRule
> metadata:
>   name: notification-service
>   namespace: routing-demo
> spec:
>   host: notification-service
>   subsets:
>     - name: v1
>       labels:
>         version: v1
>     - name: v2
>       labels:
>         version: v2
> EOF
> sleep 2
> istioctl proxy-config cluster deploy/tester -n routing-demo | grep notification
> kubectl -n routing-demo exec deploy/tester -- sh -c \
>   'for i in $(seq 1 20); do curl -s -X POST http://notification-service/notify; echo; done' | sort | uniq -c
> ```
>
> Expect something like:
>
> ```text
> notification-service.routing-demo.svc.cluster.local   80   -    outbound   EDS
> notification-service.routing-demo.svc.cluster.local   80   v1   outbound   EDS
> notification-service.routing-demo.svc.cluster.local   80   v2   outbound   EDS
>   10 ["EMAIL"]
>   10 ["EMAIL","SMS"]
> ```
>
> The `SUBSET` column goes from one `-` row to three rows. The response split is unchanged, because no rule has told anything to *use* those subsets. `EDS` in the last column is the discovery type: the proxy is told the endpoint list dynamically rather than holding fixed addresses.

## Which endpoints landed in which cluster

One level further down, `proxy-config endpoints` shows the filtered endpoint list per cluster — the EDS half of the diagram. It is the command that answers "is my subset actually selecting anything?", which is the question behind most unexplained 503s in the next part.

> [!TIP]
> **Try it — the subset's endpoint list**
>
> ```sh
> istioctl proxy-config endpoints deploy/tester -n routing-demo \
>   --cluster "outbound|80|v2|notification-service.routing-demo.svc.cluster.local"
> ```
>
> Expect something like:
>
> ```text
> ENDPOINT             STATUS      OUTLIER CHECK     CLUSTER
> 10.244.0.12:8084     HEALTHY     OK                outbound|80|v2|notification-service.routing-demo.svc.cluster.local
> ```
>
> One endpoint — the `v2` pod, selected out of the Service's two by the subset's labels. Change the subset's label to something no pod carries, re-apply, and run this again: the command succeeds and returns an empty list. That empty list is what a "silently broken" subset looks like, and it is the difference between a configuration error you can see and a 503 you cannot explain.

## What `istioctl analyze` catches here

`istioctl analyze` runs Istio's own static analysers over the objects in a namespace — the same checks the control plane would apply, plus cross-object ones that YAML schema validation cannot express. In this module the one that matters is `ReferencedResourceNotFound`: a `VirtualService` naming a subset that no `DestinationRule` defines.

It is worth running now, while the namespace holds only a `DestinationRule`, so you know what a clean result looks like before Part 2 gives you something to break.

```sh
istioctl analyze -n routing-demo
```

```text
✔ No validation issues found when analyzing namespace: routing-demo.
```

Note what `analyze` does **not** check: whether a subset's labels match any pod. Zero endpoints is legal configuration. The endpoint listing above is the only thing that tells you.

> *A `DestinationRule` builds clusters, not behaviour — it names destinations so that something else can choose between them.*

## Reference

- [DestinationRule API](https://istio.io/latest/docs/reference/config/networking/destination-rule/) — the full schema, including the `trafficPolicy` fields later sections fill in.
- [Traffic management concepts](https://istio.io/latest/docs/concepts/traffic-management/) — where subsets sit relative to the rest of the model.
- [Envoy cluster model](https://www.envoyproxy.io/docs/envoy/latest/intro/arch_overview/upstream/upstream) — what a cluster and an endpoint are in the proxy the mesh is made of.
- `istioctl proxy-config cluster --help` — the filters (`--fqdn`, `--port`, `--subset`) that make the listing readable on a real cluster.
