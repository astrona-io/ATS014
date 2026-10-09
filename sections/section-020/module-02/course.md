# Mirror Live Traffic To A Shadow Service

Weighted routing sends a share of real requests to a new version of a service. That has one cost: to see how the new version behaves under real traffic, real users must get its responses. Even at 1%, those are real requests. If the new version is broken, those users get a broken response.

**Mirroring**, also called shadowing, removes that cost. Mirroring means that the sidecar proxy of the client pod sends each request to the normal destination and *also* sends a copy of it to a second destination, the shadow. The normal destination sends the response. The proxy throws away the shadow's response and does not wait for it. The new version gets real requests at real volume, and no user ever sees its response.

The price is that a copy of a request is still a real request. If the shadow writes to a database, the write really happens.

## Learning objectives

After this module you can:

- Add a `mirror` destination to an HTTP rule of a `VirtualService`, and say which version sends the response to the client.
- Explain why a mirror is not part of the weighted split, and predict how many requests each version receives when a split and a mirror are combined.
- Control the copied share with `mirrorPercentage`, and state the default when the field is left out.
- Prove that a mirror works from the access log of the receiving pod, and explain why you do not look for a `-shadow` host name suffix on Istio 1.30.
- Find out why a mirror sends nothing, with `istioctl analyze`, the mirror policy in the client's proxy and the endpoints of the subset.
- Judge when mirroring is safe, and name the side effects that make it unsafe.

## Before you start

This module expects some knowledge of Istio routing, a running playground, and three shell helpers in your terminal.

### What you should already know

- **How the mesh works.** Istio adds a sidecar proxy (Envoy) to every pod in the mesh, and all traffic of the pod passes through it. `istiod`, the control plane, sends each proxy its configuration. You can read that configuration with `istioctl proxy-config`.
- **Subsets and routes.** A `DestinationRule` defines subsets: named groups of a Service's pods, selected by labels such as `version: v2`. A `VirtualService` sets how requests to a host are routed, and can send them to a subset.
- **Kubernetes basics.** Namespaces, Deployments, Services, pod labels, `kubectl logs` and `kubectl exec`.

### What is in your playground

Your playground is one `kind` cluster with **Istio 1.30.5** already installed. Access logs are switched on for every proxy, so each proxy writes one line per request it handles. Everything runs in the namespace **`starfleet`**:

| Workload | What it does |
| --- | --- |
| `probe` v1, v2 | HTTP echo server in two versions behind one Service on port `8000`. Its `/hostname` path returns the name of the pod that handled the request |
| `shuttle` | Test client pod in the mesh. You send every test request from here |

Every pod shows `2/2`: the application container plus the `istio-proxy` sidecar container. There is **no** `DestinationRule` and **no** `VirtualService` yet. You write them in this module.

Start your playground now, and keep it running while you read the parts:

<!-- astrona:playground -->

### Three helpers to paste first

A mirror makes two numbers differ: which version **sent the response** to the client, and which versions **received** the request. These helpers measure both. Paste them into each new terminal before you start:

```sh
mark_start() { START_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ); }
count_received()  { sleep 3; for v in v1 v2; do
  echo "probe-$v received: $(kubectl logs -n starfleet deploy/probe-$v -c probe --since-time=$START_TIME | grep -c 'GET /hostname')"
done; }
send_requests() { for i in $(seq 1 ${1:-5}); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s http://probe:8000/hostname | grep -o 'probe-v[0-9]'
done | sort | uniq -c; }
```

The helpers do three jobs:

- `send_requests` sends requests from `shuttle` (5 if you give no number) and counts which version **sent the response**.
- `mark_start` saves the current time in `START_TIME`, before a test.
- `count_received` counts the requests each version **received** since that time, from the application log of each version.

Use them together like this: `mark_start; send_requests 5; count_received`.

## The order of the parts

The module has four parts, a lab after the third part, a lab after the fourth part, and a summary at the end.

The first part adds a `mirror` to a `VirtualService` and shows where the field sits: next to `route`, not inside it. The second part mirrors requests to a version that fails every request, and shows that the client never notices. It also covers mirroring to a separate Service, and what mirroring cannot tell you.

The third part finds the proof that copies arrive, in the access log of the receiving pod, and lowers the copied share with `mirrorPercentage`. Its lab asks you to route every request to a stable version and mirror every request to a release candidate.

The fourth part covers the side effects of mirroring, reads the mirror policy from the client's proxy, and counts the load when a weighted split and a mirror work together. Its lab asks you to find and fix a mirror that sends no copies.

Mirroring and weighted routing answer the same question from opposite sides: is the new version safe? Weights show you the new version's *responses*, but real users get them. Mirroring shows you its *behaviour under real load*, but never what it would have answered. In practice you often mirror first, to find crashes and slow requests, and shift weight after that.
