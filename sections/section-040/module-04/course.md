# Locality Load Balancing And Failover

Astronaut, picture your fleet spread over several orbits. A signal to a ship in your own orbit is quick. A signal to a ship in another orbit travels further, and costs more fuel. A real cluster spread over availability zones has the same cost: traffic between zones is slower than traffic inside one zone, and most clouds charge for it.

**Locality load balancing** makes the sender's communications officer prefer ships in its own orbit. **Locality failover** is the other half: when the nearby ships stop answering, signals spill over to ships orbiting further away instead of failing, like switching to a ship orbiting another planet when the nearest one goes dark.

One fact carries the whole module, and you will prove it on your own playground:

> Istio only acts on locality for a host whose `DestinationRule` has **`outlierDetection`**. Without it there is no preference for the nearby orbit, and no failover either.

## Learning objectives

After this module you can:

- Name the labels Istio reads an endpoint's locality from, and the `region/zone/subzone` order.
- Use the `istio-locality` pod label, and say when you need it.
- Check from a live proxy that every endpoint, and the sender, has a locality.
- Explain why locality preference needs `outlierDetection`, and prove it with live signals.
- Configure `distribute` for exact cross-zone weights, and `failover` for region-level fallback, and say why they cannot be combined.
- Tell endpoint removal apart from endpoint failure, and show health-driven failover with a damaged ship.
- Choose between a mesh-wide locality setting and a per-host `DestinationRule`.

## Before you start

Every mission starts with a pre-flight check, astronaut. Make sure you have the knowledge this module expects, know what is waiting in your playground, and have two small helpers ready in your terminal.

### What you should already know

- **How the mesh works.** A proxy (the communications officer) sits beside every pod, and `istiod` (mission control) sends it orders. You can read those orders with `istioctl proxy-config`.
- **Outlier detection.** A `DestinationRule` can pull an endpoint out of formation after a number of consecutive `5xx` answers, with `consecutive5xxErrors`, `interval`, `baseEjectionTime` and `maxEjectionPercent`.
- **Kubernetes basics.** Nodes and their labels, Deployments, Services, scaling and `kubectl exec`.

### What is in your playground

Your playground is a small training solar system: one `kind` cluster with **Istio 1.30.5** already installed. Its single node is labelled with region `local` and zone `zone-a`. Everything you need is on one planet, the namespace **`starfleet`**:

| Ship | What it does |
| --- | --- |
| `shuttle` | **Your shuttle**. You send every test signal from here. It flies in the node's orbit, `local/zone-a` |
| `probe-zone-a` | The **echo probe** in orbit `local/zone-a`, the shuttle's own zone |
| `probe-zone-b` | The **echo probe** in orbit `local/zone-b` |
| `probe-zone-a-damaged` | A **damaged ship** in `local/zone-a` that answers `503` to every signal but stays ready. It starts at 0 replicas; you launch it yourself when you test failover |

All three probes answer to one beacon, the `probe` Service on port `8000`. Its `/hostname` path answers with the name of the pod that served the signal, so you can see which orbit answered.

**One adaptation matters.** Locality normally comes from the **node** a pod runs on, which needs a cluster with several nodes in different zones. Your playground has one node, so each probe declares its own orbit with the **`istio-locality`** pod label. Istio supports this override for exactly this situation. Everything about locality settings behaves the same; only the real distance between zones is missing, because every pod sits on the same machine.

There is **no** `DestinationRule` yet. Writing one is your mission in this module.

Launch your playground now, and keep it running next to you while you read the parts:

<!-- astrona:playground -->

### Two helpers to paste first

Paste these into each new terminal before you start. The first sends signals to the probe and counts which orbit answered; the second prints the status code of each signal:

```sh
count_orbits() { for i in $(seq 1 ${1:-20}); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s http://probe:8000/hostname | grep -o 'probe-zone-[ab]' || echo failed
done | sort | uniq -c; }
status_codes() { kubectl exec -n starfleet deploy/shuttle -- sh -c \
  'for i in $(seq 1 20); do curl -s -o /dev/null -w "%{http_code} " http://probe:8000/hostname; done; echo'; }
```

Use them like this: `count_orbits 20` sends 20 signals, `count_orbits 100` sends 100, and `status_codes` sends 20 and prints their codes.
