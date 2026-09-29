# ATS014 restructure + depth pass — plan and state

Decided 2026-09-29. Trigger: the reader assumed too much Istio background, and a
structural audit found content gaps and an ordering problem alongside it.

## Standing rules for every file touched

- Audience is a **beginner to Istio**, reading alone. Concrete instance before every
  general rule. Define a term on first use.
- Explain **which component does what** — Service / kube-proxy / istiod / Envoy sidecar
  confusion is the single biggest source of beginner error in this domain.
- **Mermaid** for flow, ordering, lifecycle and topology (house style:
  `~/.claude/skills/astrona-course-domain-build/references/diagrams.md`). Keep ASCII
  `text` blocks for annotated literal strings (cluster names, field-by-field breakdowns).
  Quote every node label. Under ~12 nodes. One sentence after every diagram.
- One explained concept, then at most one `> [!TIP]` checkpoint. **Never two in a row.**
- Add a `## Common pitfalls` `> [!WARNING]` block scoped to that part — no duplication
  across parts of the same module.
- Never invent command output. Trim and say it is trimmed rather than fabricate
  field order or column names.
- Landing `course.md` files stay maps: objectives, prerequisites, module order, where
  it fits. Depth lives in the parts.

## Audit findings

### Content gaps — no module covers these

| Gap | Placement decided |
| --- | --- |
| Foundations: injection, iptables, inbound/outbound, LDS/RDS/CDS/EDS, istiod push | new **section-000** module |
| `istioctl proxy-status`, `istioctl x describe pod` | **section-000** part 3 (diagnostic toolkit) |
| `rewrite`, `redirect`, header manipulation, `corsPolicy` | new **010-01 part 4** |
| Non-HTTP routing: `tcp:`, `tls:`, `sniHosts` | new **010-01 part 5** |

### Ordering

`010-02` (`Sidecar` scoping) is taught before the learner has met the registry.
**Resolved 2026-09-29: do not move it.** Section 000 part 2 now teaches the registry, the
xDS push and "every proxy is configured for the whole mesh", and ends by pointing at this
module by name. The prerequisite is satisfied immediately before section 010 begins, so the
ordering complaint no longer holds. Moving it would break the curriculum-item mapping the
root README advertises, renumber modules across the manifest and both READMEs, and change
lab paths - all for no remaining pedagogical gain. Revisit only if section 000 is ever
dropped or made optional.

### Shape

The 3-parts-per-module pattern is a template, not a measurement. Split a part when the
subject needs it; leave thin parts thin when the subject is genuinely small.

## Phases

- [x] **P0** — plan written (this file)
- [x] **P1** — section-000 foundations module: 3 parts + playground (no graded lab: nothing to configure yet)
- [x] **P2** — section-010 depth pass, incl. new 010-01 parts 4 and 5, module retitle
- [x] **P3** — section-020 depth pass
- [x] **P4** — section-030 depth pass
- [x] **P5** — section-040 depth pass (4 modules)
- [x] **P6** — section-050 depth pass
- [x] **P7** — section-060 depth pass (3 modules)
- [x] **P8** — section-070 depth pass (3 modules)
- [x] **P9** — section-080 depth pass (2 modules)
- [x] **P10** — manifest + README + section README resync; `010-02` move re-decided: NOT done, see below

One commit per phase. Each phase re-syncs `astrona.yaml` and the section README if it
added or renamed a file.

## Known follow-ups

- Landing pages carry 7 to 9 learning objectives. The generic chapter validator wants
  3 to 6 and flags 14 of the 18 pre-existing pages. Repo convention wins; do not trim
  real objectives to satisfy the linter.
- Part files fail `validate_chapter.py --module` on `## Learning objectives` and
  `## Before you start` by design — those live on the landing page. Only landing pages
  are meaningfully validated.
- **P2 must de-duplicate `010-01` against section-000.** Part 1 currently teaches
  injection, iptables, the xDS acronyms and the four-layer chain, all of which moved to
  foundations. Trim to a recap plus a link, and keep only the subset-specific material.
  Same for the `proxy-config` subcommand table in `010-01` part 3.

## Progress log

- 2026-09-29 — `010-01` part 1 expanded (194 to ~380 lines, 7 checkpoints, 3 Mermaid).
- 2026-09-29 — `010-01` part 2 expanded (206 to ~300 lines, 3 checkpoints, 2 Mermaid,
  new `VirtualService` object section, new pitfalls block).
- 2026-09-29 — P1 committed (`da9ee75`): section-000 added, manifest at 163 entries,
  all paths verified, root README resynced.
- 2026-09-29 — P2: 010-01 de-duplicated against section-000 and given parts 4 and 5
  (rewrite/redirect/headers/CORS; tcp/tls routing and protocol selection). Module
  retitled "Route Requests Within The Mesh". 010-02 expanded with a fan-out diagram,
  a memory checkpoint, a precedence diagram, a selective-Sidecar checkpoint and two
  pitfalls blocks. Manifest at 165 entries.
- 2026-09-29 — P3 to P9 complete, one commit per section. Final state: 59 parts, 19 landing
  pages, 48 Mermaid diagrams, 133 checkpoints, a pitfalls block on every part, 165 manifest
  entries, zero broken relative links, zero stacked checkpoints.

## Phase 11 — verification against real clusters, and new labs (2026-09-29)

Booted every affected playground on kind/podman and ran the checkpoints. Nine
errors in the prose were found and fixed, the largest being that `istio-proxy`
is a native sidecar on Kubernetes 1.28+ (an initContainer with
`restartPolicy: Always`), that `istioctl proxy-status` no longer prints per-channel
SYNCED columns, and that a rewrite is invisible in every access log because Istio's
format prefers `x-envoy-original-path`.

Lab coverage audit: 18 module labs and 8 capstones already cover the original 18
modules well. Three labs added for material that was taught and ungraded:

- `sections/section-000/module-01/labs/lab-01` — diagnostic: two workloads outside
  the mesh for two different reasons, neither reported by Kubernetes.
- `sections/section-010/module-01/labs/lab-02` — redirect, rewrite, header
  manipulation and corsPolicy (parts 4 and 5 of the module).
- `sections/section-030/module-01/labs/lab-02` — cookie affinity with `ttl`,
  attached through `portLevelSettings`.

**Deliberately not built**, with reasons:

- `sniHosts`, `MUTUAL`, `credentialName` — need a TLS backend or a partner CA. The
  modules say the playground cannot show them; grading them would need new fixtures.
- `040-04` `distribute` — one field, adjacent to already-graded `failover`. A lab
  for a single field is padding.
- `useSourceIp` — testable only from one tester pod, where it pins trivially and
  teaches the wrong lesson.
- `030-01`'s subset-override/replace rule — **already graded** by its lab-01; an
  earlier keyword scan missed it.

### Grader defects found and fixed while testing

- `kubectl rollout restart deployment --all` is not a valid flag. It appeared in 20
  scripts repo-wide, 19 of them masked by `|| true`, so the "restart anything that
  started before the webhook" safety net had never actually run.
- `declare -A` needs bash 4; the graders can run under macOS bash 3.2. It failed with
  an unbound-variable error **and the proctor still reported PASS**, so every new
  grader is now negative-tested against an unsolved cluster.
- A pod being deleted still reports `phase=Running`, so a grader counting running pods
  fails a correct answer mid-rollout. Graders now skip pods with a `deletionTimestamp`.

### The section-040 capstone was grading nothing

Fixing the `declare -A` bug un-masked this. Under bash 3.2 the grader hit an unbound
variable at line 32 and exited immediately, and the proctor reported **PASS** anyway —
so the capstone had never checked a single thing.

With the grader running, its own reference solution then failed check 5:
`upstream_rq_pending_overflow` never increased. The breaker was working perfectly
(49x 200, 31x 503 with the `UO` flag in telemetry); the counter simply does not exist.
Istio's default stats matcher prunes per-cluster Envoy counters, which the module 2
reader already documents — and the module 2 lab carries
`sidecar.istio.io/statsInclusionPrefixes: "cluster.outbound"` on its `fortio` pod for
exactly this reason. The capstone's `fortio` did not. Adding it makes the capstone
grade all five checks and pass legitimately.

Lesson worth keeping: a grader that cannot fail looks identical to a grader that
passes. Negative-test every one against an unsolved cluster.
