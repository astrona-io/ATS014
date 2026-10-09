# Mirror Live Traffic To A Shadow Service

Astronaut, this module is about testing a new ship without letting it talk to anyone. Sending a share of real signals to a new version has one uncomfortable side: to see how it behaves under real traffic, you have to give it real users. Even at 1%, those are somebody's signals. If the new version is broken, they get the broken answer.

**Mirroring**, also called shadowing, removes that trade-off. The communications officer on the sending ship sends each signal to the proven ship as usual, and *also* sends a copy to a test ship. The proven ship answers. The test ship's answer is thrown away, and so is any delay it causes. The new version sees real traffic, with real shapes and real volume, while no user ever sees what it says.

The cost is that a copy of a signal is still a real signal. If the test ship writes to a database, it writes.

## Learning objectives

After this module you can:

- Add a `mirror` destination to an HTTP rule, and say which answer the sender receives.
- Explain why a mirror is not part of the weighted split, and predict how many signals each version receives when a split and a mirror are combined.
- Control the copied share with `mirrorPercentage`, and state the default when it is left out.
- Prove that a mirror works from the receiving ship's flight log, and explain why the old `-shadow` host name suffix is not something to check for on Istio 1.30.
- Diagnose a mirror that silently sends nothing, from `istioctl analyze`, the proxy's mirror policy and the subset's endpoints.
- Judge when mirroring is safe, and name the side effects that make it unsafe.

## Before you start

Every mission starts with a pre-flight check, astronaut. Make sure you have the knowledge this module expects, know what is waiting in your playground, and have the helpers ready in your terminal.

### What you should already know

- **How the mesh works.** A proxy (the communications officer) sits beside every pod, and `istiod` (mission control) sends it orders. You can read those orders with `istioctl proxy-config`.
- **Docking instructions and flight plans.** A `DestinationRule` defines subsets (ship classes) over pod labels, and a `VirtualService` sends signals to them.
- **Kubernetes basics.** Namespaces, Deployments, Services, pod labels, `kubectl logs` and `kubectl exec`.

### What is in your playground

Your playground is a small training solar system: one `kind` cluster with **Istio 1.30.5** already installed, and flight logs (access logs) turned on for every proxy. Everything you need is on one planet, the namespace **`starfleet`**:

| Ship | What it does |
| --- | --- |
| `probe` v1, v2 | The **echo probe**, in two versions behind one Service on port `8000`. Its `/hostname` path answers with the name of the pod that served the signal |
| `shuttle` | **Your shuttle**. You send every test signal from here |

Every pod shows `2/2`: the app plus its communications officer (the `istio-proxy` sidecar). There is **no** `DestinationRule` and **no** `VirtualService` yet. Writing them is your mission in this module.

Launch your playground now, and keep it running next to you while you read the parts:

<!-- astrona:playground -->

### Three helpers to paste first

A mirror makes two numbers differ: which version **answered** the sender, and which versions **received** the signal. These helpers measure both. Paste them into each new terminal before you start:

```sh
mark_start() { M=$(date -u +%Y-%m-%dT%H:%M:%SZ); }
count_received()  { sleep 3; for v in v1 v2; do
  echo "probe-$v received: $(kubectl logs -n starfleet deploy/probe-$v -c probe --since-time=$M | grep -c 'GET /hostname')"
done; }
send_requests() { for i in $(seq 1 ${1:-5}); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s http://probe:8000/hostname | grep -o 'probe-v[0-9]'
done | sort | uniq -c; }
```

- `send_requests` sends signals (5 if you give no number) and counts which version **answered**.
- `mark_start` notes the time before a test.
- `count_received` counts what each version **received** since that time, from each version's own app log.

Use them together like this: `mark_start; send_requests 5; count_received`.

## Why this matters

Mirroring and weighted routing answer the same question, "is the new version safe?", from opposite ends. Weights expose real users to the new version and show you its *answers*. Mirroring exposes nobody and shows you its *behaviour under real load*, but never what it would have answered. In practice you use them in that order: mirror first, to find crashes and slow spots, then shift weight once the shadow has been quiet for a while.
