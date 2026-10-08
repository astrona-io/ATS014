# Control External Access With ServiceEntry

<!-- astrona:playground -->
> [!NOTE]
> 🧪 **Hands-on playground for this module** — a clean, throwaway machine to explore on. No task, no grading. Folder: `playground/`
>
> ```sh
> astrona run --git ssh://git@github.com/astrona-io/ATS014.git -c sections/section-070/module-01/playground
> astrona destroy ats-014-playground-070-01
> ```

Astronaut, so far every signal you steered flew between ships in your own solar system. Real applications also signal *out*: a payment API, an object store, a partner's endpoint, a package registry. These are planets in other solar systems. Traffic that leaves the cluster like this is called **egress**. Those destinations are not in the Kubernetes service registry, which means Istio knows nothing about them. It cannot route them, cannot time them out, cannot report on them, and by default does not stop them either.

Think of the **service registry** as the star chart: every planet and beacon mission control (`istiod`) knows about. A `ServiceEntry` adds a planet from another solar system to that chart. Once a host is on the chart it stops being special: the `VirtualService` and `DestinationRule` behaviour from every earlier section applies to it exactly as it does to an in-cluster Service. And `REGISTRY_ONLY` turns the default around: "signal only charted planets". Anything else falls into a black hole.

## How this module is organised

1. **[The Outbound Traffic Policy](./course-01-the-outbound-traffic-policy.md)** — the setting that decides whether unknown destinations are allowed at all, how to set it for the whole mesh or for one namespace, and how to read a refusal in the access log (`PassthroughCluster`, `BlackHoleCluster`, `502`, `000`).
2. **[The `ServiceEntry` Object](./course-02-the-serviceentry-object.md)** — the four fields that matter, what each decides, why the declared protocol is the one that unlocks everything else, and how a wildcard covers a whole domain.
3. **[A Registered Host Is An Ordinary Host](./course-03-a-registered-host-is-an-ordinary-host.md)** — applying `VirtualService` and `DestinationRule` to somebody else's API, `exportTo` scope, the `Sidecar` interaction, and the module's pitfalls.

## Learning objectives

After this module you can:

- Explain `meshConfig.outboundTrafficPolicy.mode` and the difference between `ALLOW_ANY` and `REGISTRY_ONLY`.
- Lock down one namespace with `outboundTrafficPolicy` on a `Sidecar` resource.
- Recognise the response a blocked destination produces, and tell it apart from a network failure.
- Read `PassthroughCluster`, `BlackHoleCluster` and `outbound|443||<host>` in the access log, and say which path a request took.
- Write a `ServiceEntry` for an external host, choosing correct `location` and `resolution` values.
- Explain why the declared `protocol` decides whether layer-7 features are available.
- Apply a `VirtualService` timeout and a `DestinationRule` policy to an external host.
- Scope a `ServiceEntry` with `exportTo`, and diagnose the case where a `Sidecar` resource hides one.

## Before you start

This module assumes [section 000](../../section-000/module-01/course.md): a proxy beside every pod, `istiod` programming it over xDS, and `istioctl proxy-config` as the way to see what a proxy actually holds rather than what you hoped it holds.

You need `VirtualService` from section 010 and the `timeout` field from section 040 — the last part of this module reuses both against an external host. Section 010's `Sidecar` resource matters for the final pitfall.

The playground gives you a single-node `kind` cluster with **Istio 1.30.5** installed with Helm (`istio-base` and `istiod` only — no ingress or egress gateway, because this module needs neither). The mesh is at its `ALLOW_ANY` default. The namespace **`bookinfo`** is injected and holds:

- `curl` — a client pod in the mesh. Every request in this module is sent from it.
- `httpbin` — a small test app inside the cluster (port `8000`, versions `v1` and `v2`), so you can compare an in-cluster call with an outside one.
- Mesh-wide access logs, so every sidecar writes one line per request.

No `ServiceEntry` and no `Sidecar` exist yet: the star chart only knows your own solar system. Before the first "Try it", paste this helper into your terminal. It prints the status code, the time, and curl's exit code:

```sh
call_external() { kubectl exec -n bookinfo deploy/curl -- curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" --max-time 10 "$@"; echo "  exit=$?"; }
```

A shell function lasts for one terminal, so paste it again in each new one. A result of `000` with exit `35` or `56` means the connection was cut before any HTTP answer came back.

The commands reach real hosts on the internet (`httpbin.org`, `de.wikipedia.org`, `www.google.com`). **If your environment has no outbound internet access**, what you see will be network failures rather than mesh decisions — check a plain `curl` from your machine before concluding Istio did something.

The graded lab for this module runs in its own environment (namespace `egress-demo`, a `demo`-profile install), so read its `question.md` for the names it uses.

## Where this fits

This is your launch pad for the rest of the external-traffic material. Module 2 uses a `ServiceEntry` to make an HTTPS service visible to the mesh; module 3 uses the same object with a different `location` to bring a non-Kubernetes workload of your own into it; and section 080's egress gateway routes traffic to hosts that a `ServiceEntry` registered. Get this object right and those three are variations on it.
