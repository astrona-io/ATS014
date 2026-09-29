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
**Open question, resolved last:** section-000 may remove the reason to move it. Do the
move only if it is still justified after foundations exists, and as its own commit.

### Shape

The 3-parts-per-module pattern is a template, not a measurement. Split a part when the
subject needs it; leave thin parts thin when the subject is genuinely small.

## Phases

- [ ] **P0** — plan written (this file)
- [ ] **P1** — section-000 foundations module: 3 parts + playground + graded lab
- [ ] **P2** — section-010 depth pass, incl. new 010-01 parts 4 and 5, module retitle
- [ ] **P3** — section-020 depth pass
- [ ] **P4** — section-030 depth pass
- [ ] **P5** — section-040 depth pass (4 modules)
- [ ] **P6** — section-050 depth pass
- [ ] **P7** — section-060 depth pass (3 modules)
- [ ] **P8** — section-070 depth pass (3 modules)
- [ ] **P9** — section-080 depth pass (2 modules)
- [ ] **P10** — manifest + README + section README resync; re-decide the `010-02` move

One commit per phase. Each phase re-syncs `astrona.yaml` and the section README if it
added or renamed a file.

## Progress log

- 2026-09-29 — `010-01` part 1 expanded (194 to ~380 lines, 7 checkpoints, 3 Mermaid).
- 2026-09-29 — `010-01` part 2 expanded (206 to ~300 lines, 3 checkpoints, 2 Mermaid,
  new `VirtualService` object section, new pitfalls block).
