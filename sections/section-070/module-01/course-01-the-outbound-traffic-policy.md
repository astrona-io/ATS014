# The Outbound Traffic Policy

Before the object, the policy. One setting decides whether a ship may signal a planet Istio has never heard of. It changes what a `ServiceEntry` is *for*: from a way to gain features to a way to gain permission.

## The registry, and what happens off the chart

Every sidecar, the ship's communications officer, holds a list of known hosts. This list is the **service registry**: the star chart from the landing page. It holds every Kubernetes Service, plus every `ServiceEntry` the sidecar is allowed to see.

When a pod calls a host that is **not** on the chart, the **outbound traffic policy** decides what happens:

```mermaid
flowchart TB
    R["request from a pod"] --> K{"host in registry?"}
    K -->|"yes"| N["named cluster"]
    K -->|"no"| P{"outbound policy?"}
    P -->|"ALLOW_ANY"| PT["PassthroughCluster"]
    P -->|"REGISTRY_ONLY"| BH["BlackHoleCluster"]
```

A registered host gets a named cluster such as `outbound|443||httpbin.org`, and Istio rules apply to it. `ALLOW_ANY` (the default) lets other hosts through with no rules, and `REGISTRY_ONLY` blocks them. A signal takes one of three paths, and the sidecar's access log (the ship's black box flight log) names the path for every request. Reading that name is the fastest way to know which one you are on.

## The default: `ALLOW_ANY`

Out of the box, a sidecar passes traffic to uncharted planets straight through. It does not inspect it, route it, or record much about it. It gets out of the way.

That is a deliberate choice: a mesh that cut off every outbound signal the moment it launched would be unusable. The cost is that the mesh has no visibility into, and no control over, where your workloads send data.

> [!TIP]
> **Try it — by default everything gets out**
>
> ```sh
> call_external https://httpbin.org/get
> kubectl logs -n bookinfo deploy/curl -c istio-proxy --tail=1
> ```
>
> Expect `200` and a log line that names `PassthroughCluster`. The call is allowed, but Istio knows nothing about this host: no routing, no policy, and a compromised pod could reach anything on the internet the same way.

## `REGISTRY_ONLY` — deny by default

The other mode refuses any destination that is not on the chart: "signal only charted planets". Everything else falls into a black hole. You can set it in two places.

**For the whole mesh**, it lives in the mesh configuration, `meshConfig.outboundTrafficPolicy.mode`. It is set when the control plane is installed. On an `istioctl` install, which is what the graded labs use:

```sh
istioctl install --set profile=demo \
  --set meshConfig.outboundTrafficPolicy.mode=REGISTRY_ONLY -y
```

The playground installed Istio with Helm instead, so there the same setting is a value on the `istiod` chart (`meshConfig.outboundTrafficPolicy.mode`). Either way, the install **reconciles** the existing control plane rather than creating a second one. This is the setting a security-minded exam task will usually ask for.

**For one namespace**, the `Sidecar` resource from section 010 carries its own `outboundTrafficPolicy`. A `Sidecar` describes what the proxies in a namespace (a planet) may reach. It gives each ship on that planet a smaller star chart. With no `workloadSelector`, it applies to every pod in the namespace:

```yaml
apiVersion: networking.istio.io/v1
kind: Sidecar
metadata:
  name: default
  namespace: bookinfo
spec:
  outboundTrafficPolicy:
    mode: REGISTRY_ONLY
  egress:
    - hosts:
        - "./*"
        - "istio-system/*"
```

That is the practical migration path: turn the mesh default to `REGISTRY_ONLY` eventually, but start by tightening one namespace at a time, where you can list its external dependencies without breaking everybody. It is also the method the playground uses, because it needs no reinstall.

Note what "the registry" contains, because it is broader than Kubernetes Services:

- every Kubernetes Service in every watched namespace;
- every `ServiceEntry`;
- every `WorkloadEntry` grouped by a `MESH_INTERNAL` `ServiceEntry` (module 3).

So switching to `REGISTRY_ONLY` does not break in-cluster traffic at all. It breaks exactly the calls nobody declared.

> [!TIP]
> **Try it — outside calls are blocked, inside calls are not**
>
> Save this as `sidecar-registry-only.yaml`:
>
> ```yaml
> apiVersion: networking.istio.io/v1
> kind: Sidecar
> metadata:
>   name: default
>   namespace: bookinfo
> spec:
>   outboundTrafficPolicy:
>     mode: REGISTRY_ONLY
>   egress:
>     - hosts:
>         - "./*"
>         - "istio-system/*"
> ```
>
> Apply it:
>
> ```sh
> kubectl apply -f sidecar-registry-only.yaml
> ```
>
> Then check the result:
>
> ```sh
> call_external https://httpbin.org/get
> call_external http://httpbin:8000/get
> kubectl logs -n bookinfo deploy/curl -c istio-proxy --tail=2
> ```
>
> Expect `000 exit=35` for `httpbin.org` and `200` for the `httpbin` inside the cluster. The log shows `BlackHoleCluster` with the flag `UH` for the blocked call. Nothing about the pod or the network changed — only the policy.

Keep this `Sidecar` applied. Parts 2 and 3 build on it.

## The signature of a refusal

A blocked signal does not come back with a message that names the policy. What you see depends on whether the sidecar can read the request:

- **HTTPS (or any TLS)** to a blocked host: the sidecar only sees encrypted bytes, so it simply drops the connection. curl shows `000` with exit `35` (or `56`).
- **Plain HTTP** to a blocked host: if the proxy has an HTTP listener for that port, it answers with **HTTP 502** itself. If it has no listener for that port at all, the connection is dropped and you see `000`, as with HTTPS.

The playground's scoped `Sidecar` leaves the proxy with no plain-HTTP listener on port 80, so expect `000` there. On a mesh-wide `REGISTRY_ONLY` install with other services on port 80 — the graded lab — the same call returns `502`.

Recognising these matters more than the YAML, because the alternatives look similar and mean different things:

| Symptom | Usually means |
| --- | --- |
| `BlackHoleCluster` in the sidecar's log | the mesh refused it — the host is not in the registry |
| `502` from the sidecar on plain HTTP | the mesh refused it — same cause, seen from an HTTP listener |
| `000` with no `BlackHoleCluster` line | nothing answered at all — DNS, the network, or the host is down |
| `504` | a route timeout fired (section 040) |
| DNS resolution failure | the name does not resolve in the cluster at all |

So the access log is the tie-breaker, astronaut. A refusal is a *mesh decision*: DNS worked, the network is fine, and the proxy simply had no cluster to send the request to.

| Log cluster | Meaning |
| --- | --- |
| `PassthroughCluster` | unknown host, let through (`ALLOW_ANY`) |
| `BlackHoleCluster` | unknown host, blocked (`REGISTRY_ONLY`) |
| `outbound\|443\|\|httpbin.org` | a host registered by a `ServiceEntry` |

> *Under `REGISTRY_ONLY` a refusal is a mesh decision — `BlackHoleCluster` in the log, and `502` or `000` at the client, while DNS and the network are fine.*

## Common pitfalls

> [!WARNING]
> **Assuming the default denies external traffic.** `ALLOW_ANY` is the install default: anything not in the registry is passed through unexamined.
>
> **Reading `ALLOW_ANY` as "no policy needed".** Traffic leaving under it is opaque to the mesh — no routing, no telemetry, no policy, and no record of where it went.
>
> **Switching to `REGISTRY_ONLY` without an inventory.** Every undeclared external dependency starts failing at once, and the failures look like the application's.
>
> **Expecting a clear error on refusal.** The signature is a dropped connection (`000`) or a `502`, not a message naming the policy. Read the access log for `BlackHoleCluster`.
>
> **Setting the mesh-wide value when one namespace needs it.** A `Sidecar` carries its own `outboundTrafficPolicy` for exactly this.
>
> **Treating `REGISTRY_ONLY` as a firewall.** It is enforced by the sidecar, so a pod without a sidecar is not limited at all. Real enforcement needs a `NetworkPolicy` and an egress gateway (section 080) as well.
