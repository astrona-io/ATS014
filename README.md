# ATS014 — Traffic Management (Istio Certified Associate)

Course material for the **Traffic Management** domain of the Istio Certified Associate (ICA) exam, which is **35% of the exam** — the largest single domain.

Built and verified against **Istio 1.30.5**.

The course is about one thing: **requests** between workloads. Istio adds a sidecar proxy (Envoy) to every pod, and all traffic in and out of the pod passes through it. Istio's control plane, `istiod`, sends each proxy its configuration: where requests may go, how long to wait for a response, and what to do when an endpoint fails. This course teaches you to write that configuration and to prove it works on a real Kubernetes cluster.

The repository has four layers:

| Layer | Path | What it is |
| --- | --- | --- |
| **Manifest** | `astrona.yaml` | The course outline the platform reads — every reading and lab, in order |
| **Reading** | `sections/section-0N0/module-0M/` | A short landing page, ordered parts that teach one idea each with hands-on steps, and a summary |
| **Practice** | `.../module-0M/labs/lab-0N/` and `.../playground/` | Graded labs placed right after the part they practise, and one ungraded sandbox per module |
| **Integration** | `sections/section-0N0/capstone/labs/lab-01/` | One graded capstone per section, combining that section's modules |

How to work through a module: read its parts with its playground running alongside. When a part ends with **Your mission**, pause the playground and take that lab without looking at the solution. The last page of the module closes it and removes the playground. Finish each section with its capstone, a bigger graded lab that combines everything in that section.

---

## Start Here

New to the course? Read the **[Introduction](sections/intro/README.md)** first. It explains how the course is laid out, how to get your machine ready, how the content is made, who maintains it, and how to report a mistake.

---

## What The Domain Covers

The Traffic Management domain is seven topics. Every section below is named after the one it teaches, so the curriculum and the repository read the same way:

| # | Exam topic | Section |
| --- | --- | --- |
| 1 | Configuring Ingress and Egress Traffic | [060 — ingress](sections/section-060) and [080 — egress](sections/section-080) |
| 2 | Configuring Routing within a Service Mesh | [010](sections/section-010) |
| 3 | Defining Traffic Policies with Destination Rules | [030](sections/section-030) |
| 4 | Configuring Traffic Shifting | [020](sections/section-020) |
| 5 | Connecting In-Mesh Workloads to External Workloads and Services | [070](sections/section-070) |
| 6 | Using Resilience Features (circuit breaking, failover, outlier detection, timeouts, retries) | [040](sections/section-040) |
| 7 | Using Fault Injection | [050](sections/section-050) |

Section [000](sections/section-000) is not an exam topic. It covers the basics the other seven assume: what a sidecar proxy is, how `istiod` sends it configuration, and how to read a proxy's live configuration.

## Sections

| Section | Title | Modules | Curriculum item |
| --- | --- | --- | --- |
| [000](sections/section-000) | Mesh Foundations | 1 | *prerequisite — not an exam item* |
| [010](sections/section-010) | Configuring Routing Within A Service Mesh | 3 | Configuring Routing within a Service Mesh |
| [020](sections/section-020) | Configuring Traffic Shifting | 2 | Configuring Traffic Shifting |
| [030](sections/section-030) | Defining Traffic Policies With Destination Rules | 1 | Defining Traffic Policies with Destination Rules |
| [040](sections/section-040) | Using Resilience Features (Circuit Breaking, Failover, Outlier Detection, Timeouts, Retries) | 4 | Using Resilience Features |
| [050](sections/section-050) | Using Fault Injection | 1 | Using Fault Injection |
| [060](sections/section-060) | Configuring Ingress And Egress Traffic — Ingress | 3 | Configuring Ingress and Egress Traffic |
| [070](sections/section-070) | Connecting In-Mesh Workloads To External Workloads And Services | 3 | Connecting In-Mesh Workloads to External Workloads and Services |
| [080](sections/section-080) | Configuring Ingress And Egress Traffic — Egress | 2 | Configuring Ingress and Egress Traffic |

**20 modules · 80 parts · 48 graded labs · 8 capstones · 20 playgrounds.**

The reading pages and labs are listed in [`astrona.yaml`](astrona.yaml): 245 entries across the introduction and the 9 sections, in the order a learner should work through them. Lab solutions (`solution.md`) are left out on purpose, so learners try each lab before they see the answer.

Sections are ordered so each needs only what came before. Section 000 is foundations — what a sidecar is, how `istiod` programs it, and how to read a proxy's live configuration — because every section after it assumes all three. `VirtualService` and `DestinationRule` are introduced first because everything else is a field on one of them; `ServiceEntry` (070) precedes the egress gateway (080) that depends on it.

---

## Modules

Each module is a landing page, its ordered parts and a closing page. The landing page lists the parts in order, and each section's overview lists every part with the labs that follow it.

| Module | Reader | Parts | Graded labs |
| --- | --- | --- | --- |
| 000-01 | [How A Request Moves Through The Mesh](sections/section-000/module-01/course.md) | 5 | 2 |
| 010-01 | [Route Requests Within The Mesh](sections/section-010/module-01/course.md) | 9 | 5 |
| 010-02 | [Scope Proxy Configuration With The Sidecar Resource](sections/section-010/module-02/course.md) | 4 | 2 |
| 010-03 | [Apply And Remove Traffic Rules Safely](sections/section-010/module-03/course.md) | 2 | 1 |
| 020-01 | [Shift Traffic With Weighted Routing](sections/section-020/module-01/course.md) | 3 | 2 |
| 020-02 | [Mirror Live Traffic To A Shadow Service](sections/section-020/module-02/course.md) | 3 | 2 |
| 030-01 | [Load Balancer Policy And Session Affinity](sections/section-030/module-01/course.md) | 4 | 3 |
| 040-01 | [Timeouts And Retries](sections/section-040/module-01/course.md) | 4 | 3 |
| 040-02 | [Circuit Breaking With Connection Pool Limits](sections/section-040/module-02/course.md) | 3 | 2 |
| 040-03 | [Outlier Detection And Endpoint Ejection](sections/section-040/module-03/course.md) | 3 | 2 |
| 040-04 | [Locality Load Balancing And Failover](sections/section-040/module-04/course.md) | 3 | 3 |
| 050-01 | [Fault Injection With Delays And Aborts](sections/section-050/module-01/course.md) | 4 | 3 |
| 060-01 | [Expose A Service With An Istio Ingress Gateway](sections/section-060/module-01/course.md) | 4 | 3 |
| 060-02 | [Expose A Service With A Kubernetes Ingress](sections/section-060/module-02/course.md) | 3 | 2 |
| 060-03 | [Ingress With The Kubernetes Gateway API](sections/section-060/module-03/course.md) | 4 | 3 |
| 070-01 | [Control External Access With ServiceEntry](sections/section-070/module-01/course.md) | 4 | 2 |
| 070-02 | [TLS Origination For External Services](sections/section-070/module-02/course.md) | 4 | 2 |
| 070-03 | [Add External Workloads With WorkloadEntry](sections/section-070/module-03/course.md) | 4 | 2 |
| 080-01 | [Route External Traffic Through An Egress Gateway](sections/section-080/module-01/course.md) | 5 | 2 |
| 080-02 | [TLS Origination At The Egress Gateway](sections/section-080/module-02/course.md) | 5 | 2 |

---

## Running a playground

Every module has one: a **kind** cluster with Istio 1.30.5 installed and the module's starting workloads applied. It has no Istio traffic configuration on purpose, because writing that configuration is the exercise.

Every playground runs **the Starfleet**: the Bookinfo sample app from the Istio documentation, with space names (`bridge`, `cargo`, `scout` v1, v2 and v3, `navcom`) in namespace `starfleet`, plus the `shuttle` test client and any extra workloads the module needs. The playgrounds install Istio with Helm (`istiod`, plus a gateway where the module needs one), so you need `istioctl` on your own machine. Each one has `examples/` with ready YAML files, and most also have `docs/practice.md` with an exam-style task. A few older graded labs and capstones still use their own small apps.

```bash
astrona run --git ssh://git@github.com/astrona-io/ATS014.git -c sections/section-010/module-01/playground
astrona destroy ats-014-playground-010-01
```

Playgrounds are **ungraded**: no task, no `astrona submit`, no pass/fail. Break it as often as you like. Each one's `docs/overview.md` lists what is in the box and things worth trying, including deliberate mistakes. Breaking things on purpose is often the fastest way to learn what a failure looks like.

`astrona destroy` takes the environment **name** (`metadata.name` in the playground's `config.yaml`), not the configuration path.

## Running a lab or capstone

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-010/module-01/labs/lab-01
astrona submit -c sections/section-010/module-01/labs/lab-01
```

Labs are **graded** against the live state of the cluster. Each carries a `question.md` (the task), a `solution.md` (a full walkthrough, plus the mistakes that fail it), and a validation script that checks behaviour rather than just object fields.

---

## Environment notes

- **No load balancer.** On `kind`, a gateway Service's `EXTERNAL-IP` stays `<pending>`. The ingress and egress material uses `kubectl port-forward`; this is expected, not a fault.
- **Outbound internet.** The *playgrounds* for 070-01, 070-02, 080-01 and 080-02 reach real hosts on the internet (for example `httpbin.org`). Without outbound access you will see network errors rather than mesh behaviour. **Every graded lab and capstone runs entirely offline** — their "external" endpoints are pods deliberately kept out of the mesh registry.
- **Locality (040-04).** Deriving locality from node labels needs a multi-node cluster, so that playground declares it with the `istio-locality` pod label instead. Its `docs/overview.md` says what that changes.
- **Gateway API version.** The Gateway API module (060-03) and its labs pin a Gateway API CRD release. Gateway API and Istio release on their own schedules — check the Istio release notes for the supported pairing before changing either version.
