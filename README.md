# ATS014 — Traffic Management (Istio Certified Associate)

Course material for the **Traffic Management** domain of the Istio Certified Associate (ICA) exam, which is **35% of the exam** — the largest single domain.

Built and verified against **Istio 1.30.5**.

The repository has three layers:

| Layer | Path | What it is |
| --- | --- | --- |
| **Manifest** | `astrona.yaml` | The course outline the platform reads — every reading and lab, in order |
| **Reading** | `sections/section-0N0/module-0M/` | A short landing page plus ordered deep-dive parts, each with hands-on "Try it" checkpoints |
| **Practice** | `.../module-0M/labs/lab-01/` and `.../playground/` | One graded lab per module, and one ungraded sandbox per module (section 000 is reading + playground only) |
| **Integration** | `sections/section-0N0/capstone/labs/lab-01/` | One graded capstone per section, combining that section's modules |
| **Source** | `domains/traffic-management/` | The original exam-style study labs each module was built from |

Read a module's parts, run its playground alongside, then take the module lab without looking at the solution — and finish the section with its capstone.

---

## Sections

| Section | Title | Modules | Curriculum item |
| --- | --- | --- | --- |
| [000](sections/section-000) | Mesh Foundations | 1 | *prerequisite — not an exam item* |
| [010](sections/section-010) | Configuring Routing Within A Service Mesh | 2 | Configuring Routing within a Service Mesh |
| [020](sections/section-020) | Configuring Traffic Shifting | 2 | Configuring Traffic Shifting |
| [030](sections/section-030) | Defining Traffic Policies With Destination Rules | 1 | Defining Traffic Policies with Destination Rules |
| [040](sections/section-040) | Using Resilience Features | 4 | Using Resilience Features |
| [050](sections/section-050) | Using Fault Injection | 1 | Using Fault Injection |
| [060](sections/section-060) | Configuring Ingress Traffic | 3 | Configuring Ingress and Egress Traffic |
| [070](sections/section-070) | Connecting In-Mesh Workloads To External Workloads And Services | 3 | Connecting In-Mesh Workloads to External Workloads and Services |
| [080](sections/section-080) | Egress Gateways | 2 | Configuring Ingress and Egress Traffic |

**19 modules · 57 deep-dive parts · 18 graded labs · 8 capstones · 19 playgrounds.**

All of it is listed in [`astrona.yaml`](astrona.yaml) — 163 entries across the 9 sections, in the order a learner should work through them.

Sections are ordered so each needs only what came before. Section 000 is foundations — what a sidecar is, how `istiod` programs it, and how to read a proxy's live configuration — because every section after it assumes all three. `VirtualService` and `DestinationRule` are introduced first because everything else is a field on one of them; `ServiceEntry` (070) precedes the egress gateway (080) that depends on it.

---

## Modules

Each module is a landing page plus its ordered parts. The landing page links them in order.

| Module | Reader | Graded lab | Source lab |
| --- | --- | --- | --- |
| 000-01 | [How A Request Moves Through The Mesh](sections/section-000/module-01/course.md) | *none — reading + playground* | — |
| 010-01 | [Route Requests By Header, URI And Query Parameter](sections/section-010/module-01/course.md) | [lab](sections/section-010/module-01/labs/lab-01) | [`01-request-routing…`](domains/traffic-management/01-request-routing-headers-uri-query) |
| 010-02 | [Scope Proxy Configuration With The Sidecar Resource](sections/section-010/module-02/course.md) | [lab](sections/section-010/module-02/labs/lab-01) | [`17-sidecar-resource-scoping`](domains/traffic-management/17-sidecar-resource-scoping) |
| 020-01 | [Shift Traffic With Weighted Routing](sections/section-020/module-01/course.md) | [lab](sections/section-020/module-01/labs/lab-01) | [`02-traffic-shifting…`](domains/traffic-management/02-traffic-shifting-weighted-canary) |
| 020-02 | [Mirror Live Traffic To A Shadow Service](sections/section-020/module-02/course.md) | [lab](sections/section-020/module-02/labs/lab-01) | [`03-traffic-mirroring`](domains/traffic-management/03-traffic-mirroring) |
| 030-01 | [Load Balancer Policy And Session Affinity](sections/section-030/module-01/course.md) | [lab](sections/section-030/module-01/labs/lab-01) | [`08-load-balancing…`](domains/traffic-management/08-load-balancing-and-session-affinity) |
| 040-01 | [Timeouts And Retries](sections/section-040/module-01/course.md) | [lab](sections/section-040/module-01/labs/lab-01) | [`04-timeouts-and-retries`](domains/traffic-management/04-timeouts-and-retries) |
| 040-02 | [Circuit Breaking With Connection Pool Limits](sections/section-040/module-02/course.md) | [lab](sections/section-040/module-02/labs/lab-01) | [`05-circuit-breaking…`](domains/traffic-management/05-circuit-breaking-connection-pool) |
| 040-03 | [Outlier Detection And Endpoint Ejection](sections/section-040/module-03/course.md) | [lab](sections/section-040/module-03/labs/lab-01) | [`06-outlier-detection-ejection`](domains/traffic-management/06-outlier-detection-ejection) |
| 040-04 | [Locality Load Balancing And Failover](sections/section-040/module-04/course.md) | [lab](sections/section-040/module-04/labs/lab-01) | [`09-locality-load-balancing…`](domains/traffic-management/09-locality-load-balancing-and-failover) |
| 050-01 | [Fault Injection With Delays And Aborts](sections/section-050/module-01/course.md) | [lab](sections/section-050/module-01/labs/lab-01) | [`07-fault-injection…`](domains/traffic-management/07-fault-injection-delay-abort) |
| 060-01 | [Expose A Service With An Istio Ingress Gateway](sections/section-060/module-01/course.md) | [lab](sections/section-060/module-01/labs/lab-01) | [`10-ingress-gateway-http`](domains/traffic-management/10-ingress-gateway-http) |
| 060-02 | [Expose A Service With A Kubernetes Ingress](sections/section-060/module-02/course.md) | [lab](sections/section-060/module-02/labs/lab-01) | [`11-ingress-with-kubernetes-ingress`](domains/traffic-management/11-ingress-with-kubernetes-ingress) |
| 060-03 | [Ingress With The Kubernetes Gateway API](sections/section-060/module-03/course.md) | [lab](sections/section-060/module-03/labs/lab-01) | [`12-ingress-with-gateway-api`](domains/traffic-management/12-ingress-with-gateway-api) |
| 070-01 | [Control External Access With ServiceEntry](sections/section-070/module-01/course.md) | [lab](sections/section-070/module-01/labs/lab-01) | [`13-egress-serviceentry…`](domains/traffic-management/13-egress-serviceentry-external-access) |
| 070-02 | [TLS Origination For External Services](sections/section-070/module-02/course.md) | [lab](sections/section-070/module-02/labs/lab-01) | [`14-egress-tls-origination`](domains/traffic-management/14-egress-tls-origination) |
| 070-03 | [Add External Workloads With WorkloadEntry](sections/section-070/module-03/course.md) | [lab](sections/section-070/module-03/labs/lab-01) | [`18-workloadentry…`](domains/traffic-management/18-workloadentry-external-workloads) |
| 080-01 | [Route External Traffic Through An Egress Gateway](sections/section-080/module-01/course.md) | [lab](sections/section-080/module-01/labs/lab-01) | [`15-egress-gateway-routing`](domains/traffic-management/15-egress-gateway-routing) |
| 080-02 | [TLS Origination At The Egress Gateway](sections/section-080/module-02/course.md) | [lab](sections/section-080/module-02/labs/lab-01) | [`16-egress-gateway-tls-origination`](domains/traffic-management/16-egress-gateway-tls-origination) |

---

## Running a playground

Every module has one: a **kind** cluster with Istio 1.30.5 (`demo` profile) installed and the module's starting workloads applied — and deliberately no Istio traffic configuration, because writing that is the module's subject.

```bash
astrona run --git ssh://git@github.com/astrona-io/ATS014.git -c sections/section-010/module-01/playground
astrona destroy ats-014-playground-010-01
```

Playgrounds are **ungraded**: no task, no `astrona submit`, no pass/fail. Each one's `docs/overview.md` lists what is in the box and things worth trying — including deliberate mistakes, which are often the fastest way to learn a failure signature.

`astrona destroy` takes the environment **name** (`metadata.name` in the playground's `config.yaml`), not the config path.

## Running a lab or capstone

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-010/module-01/labs/lab-01
astrona submit -c sections/section-010/module-01/labs/lab-01
```

Labs are **graded** against live cluster state. Each carries a `question.md` (the task), a `solution.md` (a full walkthrough, plus the mistakes that fail it), and a validation script that checks behaviour rather than just object fields.

---

## Environment notes

- **No load balancer.** On `kind`, a gateway Service's `EXTERNAL-IP` stays `<pending>`. The ingress and egress material uses `kubectl port-forward`; this is expected, not a fault.
- **Outbound internet.** The section 070 and 080 *playgrounds* reach real hosts (`httpbin.org`, `example.com`). Without outbound access you will see network errors rather than mesh behaviour. **Every graded lab and capstone runs entirely offline** — their "external" endpoints are pods deliberately kept out of the mesh registry.
- **Locality (040-04).** Deriving locality from node labels needs a multi-node cluster, so that playground declares it with the `istio-locality` pod label instead. Its `docs/overview.md` says what that changes; the matching lab under `domains/` targets a real multi-node cluster.
- **Gateway API version.** Section 060 module 3 and its lab pin a Gateway API CRD release. Gateway API and Istio release on their own schedules — check the Istio release notes for the supported pairing before changing either version.

---

## Working the source labs

`domains/traffic-management/` holds the original exam-style study lab each module was derived from, with `manifests/lab-start.yaml` and `manifests/solution.yaml`. They assume a cluster with Istio already installed and are written for the exam's own rhythm: read the task, write the objects, verify against live cluster state.

See [`domains/traffic-management/README.md`](domains/traffic-management/README.md) for the full list and which upstream Killercoda scenario each derives from.
