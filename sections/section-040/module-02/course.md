# Circuit Breaking With Connection Pool Limits

Astronaut, a timeout protects one signal. A **circuit breaker** protects a ship while the ship it depends on is struggling. It is the ship raising its shields.

Picture a big ship whose docking ports are all taken. More ships keep arriving and circle around it, waiting for a free port. Soon the whole sky is jammed, and ships that should be flying elsewhere are stuck in the queue. The safe move is to raise the shields early: tell new ships "no room, go somewhere else" right away.

That is what this module teaches. Without a limit, signals pile up while they wait for a slow service. Memory and workers fill up with work that will probably fail anyway, the waiting ship gets slow too, and the ships that call *it* start to suffer. Nothing crashed, yet a whole chain of services is down.

Istio's answer is simple. You cap how much work may be open to one service at the same time. Anything above that cap is refused **at once** with a `503`. A fast, honest "no" is better than a slow one.

## Learning objectives

After this module you can:

- Configure `trafficPolicy.connectionPool` with TCP and HTTP limits, and name what each setting caps.
- Explain why a limit on signals at the same time is not a limit on signals in total, and design a test that really trips it.
- Explain why `http1MaxPendingRequests` decides whether an HTTP/1 breaker trips at all.
- Identify a circuit-breaker refusal by the `UO` response flag and the `upstream_rq_pending_overflow` counter.
- Read the live limits out of a proxy with `istioctl proxy-config cluster`, on the sending side and on the receiving side.
- Explain why a sender's own refusals are never retried, and how retries still multiply the load on a struggling service.

## Before you start

Every mission starts with a pre-flight check, astronaut. Make sure you have the knowledge this module expects, know what is in your playground, and have two helpers ready in your terminal.

### What you should already know

- **How the mesh works.** A proxy (the communications officer) sits beside every pod, and `istiod` (mission control) sends it orders. You can read those orders with `istioctl proxy-config`.
- **`DestinationRule` and `trafficPolicy`.** This module uses the same object and the same field, with new keys inside.
- **A retry policy on a `VirtualService`.** The last part uses `retries` with `attempts` and `retryOn`.

### What is in your playground

Your playground is a training solar system: one `kind` cluster with **Istio 1.30.5** installed with Helm, and flight logs switched on for every ship. Everything lives on one planet, the namespace **`starfleet`**:

| Ship | What it does |
| --- | --- |
| `probe` v1 and v2 | The **echo probe**: two pods behind one Service on port `8000`. It is the service you put shields around |
| `fortio` | The **load generator**: it fires many signals **at the same time**. Its pod has two containers, `fortio` and `istio-proxy`, so some commands pick one with `-c` |
| `shuttle` | **Your shuttle**: a client for single signals, one at a time |

This module is all about signals at the same time. A `curl` loop only ever sends one at a time, which is why `fortio` is the main tool here. Its communications officer is also set up to keep the circuit-breaker counters you read later.

There is **no `DestinationRule`** yet, so there is no limit at all.

Launch your playground now, and keep it running next to you while you read the parts:

<!-- astrona:playground -->

### Two helpers to paste first

Paste these into each new terminal. Each comment says what the helper does:

```sh
# 30 signals to the probe over N parallel connections, from fortio; prints the status-code summary
load_test() { kubectl exec -n starfleet deploy/fortio -c fortio -- \
  fortio load -c "$1" -qps 0 -n 30 -loglevel Warning http://probe:8000/get 2>&1 | grep -E "^Code"; }
# fortio's own circuit-breaker counters for the probe
overflow_stats() { kubectl exec -n starfleet deploy/fortio -c istio-proxy -- \
  pilot-agent request GET stats 2>/dev/null | grep 'probe.starfleet' | grep -E 'pending_overflow|cx_overflow|pending_active'; }
```

`load_test 3` means "30 signals, 3 open at any moment, as fast as possible".
