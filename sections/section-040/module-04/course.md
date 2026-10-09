# Locality Load Balancing And Failover

A real cluster often runs its nodes in several availability zones. An **availability zone** is a separate data center area inside one cloud region. A request between two zones is slower than a request inside one zone, and most clouds charge for traffic between zones.

**Locality load balancing** makes the sidecar proxy of the client pod prefer endpoints in its own zone. The **sidecar proxy** (Envoy) is the proxy container that Istio adds to each pod; it picks the endpoint for every outgoing request. **Locality failover** is the other half: when the endpoints in the client's own zone stop working, the proxy sends requests to endpoints further away instead of failing them.

One fact carries the whole module, and you will prove it on your own playground:

> Istio only acts on locality for a host whose `DestinationRule` has **`outlierDetection`**. Without it there is no preference for the client's own zone, and no failover either.

## Learning objectives

After this module you can:

- Name the labels Istio reads an endpoint's locality from, and the `region/zone/subzone` order.
- Use the `istio-locality` pod label, and say when you need it.
- Check from a live proxy that every endpoint, and the client, has a locality.
- Explain why locality preference needs `outlierDetection`, and prove it with live requests.
- Configure `distribute` for exact weights between zones, and `failover` for a fallback region, and say why they cannot be combined.
- Tell endpoint removal apart from endpoint failure, and show failover with a pod that fails every request.
- Choose between a mesh-wide locality setting and a per-host `DestinationRule`.

## Before you start

This module expects some knowledge, a running playground, and two small shell helpers in your terminal.

### What you should already know

- **How the mesh works.** A sidecar proxy runs beside every application container. `istiod`, Istio's control plane, sends configuration to every proxy. You can read that configuration with `istioctl proxy-config`.
- **Outlier detection.** A `DestinationRule` can eject an endpoint, that is, stop sending it requests for a while, after a number of consecutive `5xx` responses. The fields are `consecutive5xxErrors`, `interval`, `baseEjectionTime` and `maxEjectionPercent`.
- **Kubernetes basics.** Nodes and their labels, Deployments, Services, scaling and `kubectl exec`.

### What is in your playground

Your playground is one `kind` cluster with **Istio 1.30.5** already installed. Its single node has the region label `local` and the zone label `zone-a`. All workloads run in the namespace **`starfleet`**, which has sidecar injection switched on:

| Workload | What it does |
| --- | --- |
| `shuttle` | Test client pod. You send every test request from here. It runs in the node's locality, `local/zone-a` |
| `probe-zone-a` | HTTP echo server in locality `local/zone-a`, the same zone as `shuttle` |
| `probe-zone-b` | HTTP echo server in locality `local/zone-b` |
| `probe-zone-a-damaged` | A pod in `local/zone-a` that returns `503` to every request but stays ready. It starts at 0 replicas; you scale it up when you test failover |

All three probe Deployments sit behind one Service, `probe`, on port `8000`. Its `/hostname` path returns the name of the pod that served the request, so you can see which zone answered.

**One adaptation matters.** Locality normally comes from the **node** a pod runs on, so you would need several nodes in different zones. Your playground has one node, so each probe sets its own locality with the **`istio-locality`** pod label. Istio supports this label for exactly this case. All locality settings behave the same; only the real distance between zones is missing, because every pod runs on the same machine.

There is **no** `DestinationRule` yet. You write it yourself in this module.

Start your playground now, and keep it running while you read the parts:

<!-- astrona:playground -->

### Two helpers to paste first

Paste these into each new terminal before you start. The first sends requests to the probe and counts which zone answered. The second prints the HTTP status code of each request:

```sh
count_zones() { for i in $(seq 1 ${1:-20}); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s http://probe:8000/hostname | grep -o 'probe-zone-[ab]' || echo failed
done | sort | uniq -c; }
status_codes() { kubectl exec -n starfleet deploy/shuttle -- sh -c \
  'for i in $(seq 1 20); do curl -s -o /dev/null -w "%{http_code} " http://probe:8000/hostname; done; echo'; }
```

`count_zones 20` sends 20 requests, `count_zones 100` sends 100, and `status_codes` sends 20 and prints their status codes.

## The order of the parts

The module has three parts, each followed by a lab, and a summary at the end.

The first part shows where an endpoint's locality comes from: the node labels, and the `istio-locality` pod label that overrides them. It also shows how to read the locality of every endpoint from the client's proxy. Its lab asks you to find and fix a probe that runs in the wrong zone.

The second part proves that the locality preference only acts when `outlierDetection` is present. It then shows the two ways to control the preference: exact weights with `distribute`, and a fallback region with `failover`. Its lab asks you to split traffic between two zones with fixed weights.

The third part shows the difference between an endpoint that is removed and an endpoint that fails while it stays ready. Only outlier detection notices the second case. It also compares the mesh-wide locality setting with a per-host `DestinationRule`. Its lab asks you to move traffic away from a zone whose only endpoint fails every request.
