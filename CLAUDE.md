# Writing style for this repo

All study text here (course pages, lab docs, READMEs, comments in YAML and
scripts) is for people learning a technical subject, often for a
certification exam. Many of them are not native English speakers and have no
university degree.

## Plain English

Write the text in Plain English for a general adult audience (18+) without a
university degree. The content must be highly accessible and easy to
understand for non-technical readers, without feeling childish.

Strict guidelines:

1. Target a Flesch-Kincaid Grade Level of 8 or 9 (equivalent to a standard
   newspaper article).
2. Avoid all technical jargon, acronyms, and corporate buzzwords. If a
   technical term is necessary, explain it immediately using an everyday
   analogy.
3. Keep sentences conversational and direct. Split long sentences into two.
4. Use short paragraphs (max 3-4 sentences per paragraph) and clear
   subheadings to make the text scannable.
5. Use the active voice (e.g., "We did this" instead of "This was done by us").

## How this applies to course material

- **Know which file you are in.** A module has a short landing page and a few
  deep-dive parts. The landing page is a map: goals, what to know first, the
  order of the parts, where it fits. The real teaching goes in the parts. A lab
  has a task, a step-by-step solution and a short intro. Keep each file to its
  job. Do not add "Prerequisite: ... Next: ..." navigation lines to pages;
  the landing page and the course outline already give the order.
- **Keep each part short.** One idea per part, about 5 to 8 minutes of
  reading and at most about 8 command blocks, so a learner can finish it with
  the playground in one sitting of about 15 minutes. Split at a natural seam
  where each half ends with something the learner has seen work. Never split
  only to hit a number. When you split, renumber the files, fix every "Part N"
  reference in the module, the wrap-up links and `astrona.yaml`.
- **Every heading gets an intro.** A `##` section that has `###`
  subsections starts with one to three sentences that say what the section
  is about and why it matters, before the first `###`. Never put a `###`
  directly under a `##`.
- **Every module stands on its own.** Never refer to other sections or
  modules: no "see section 040", "as module 3 showed", "you met this in
  section 000", and no links to pages in another module. If the reader needs
  a fact from elsewhere, state the fact directly in one or two sentences.
  This also goes for parts of the same module: never write "Part 2 shows",
  "from Part 1" or "as in Part 3". Say the fact itself ("the commands below
  need the `scout` `DestinationRule` applied"). The wrap-up page is the one
  exception: it recaps each part and links to it.
  The landing page does not have a "Where this fits" section.
- **Write words out in full.** Do not use informal short forms in prose:
  write "communications", "configuration", "repository", "administrator",
  "for example" and "that is", never "comms", "config", "repo", "admin",
  "e.g." or "i.e.". Names in code, commands and file paths stay as they are.
- **Exam terms stay.** The product's own names are what the reader must learn
  (for example a resource kind, a field, a command). Keep them, but explain
  each one in plain words, with an everyday analogy, the first time it appears
  in a file. Spell out acronyms on first use, with a short plain meaning.
- **Analogies come from space, and the reader is an astronaut.** When a term
  needs an everyday picture, use space: spaceships, planets, solar systems,
  space stations, mission control, signals, docking, star charts, airlocks,
  even the Death Star. Talk to the reader as an astronaut (for example "your
  first mission", "astronaut, check your flight log"), but not in every
  sentence. Requests are **signals** that ships send to each other. Use one
  analogy per hard idea, keep it short, and keep it the same everywhere (if
  the repository has an analogy glossary, use it). The analogy helps the reader; it
  never replaces the real term, and it never changes code or output.
- **Show one real example before the rule.** Start with a concrete case the
  reader can run, then give the general rule.
- **Say which part does the work.** Readers often mix up the parts of a system
  that sit close together. Whenever something happens, say which component
  did it.
- **Never change code to fit the style.** Commands, configuration files, field
  names, resource names, log lines and command output stay exactly as they
  are. They were run and checked on a real system. Never make up command
  output. If you shorten it, say that you did.
- **Prose only.** The grade-level and sentence rules apply to explanations.
  They do not apply to code blocks, tables of field names or reference lists
  (those may stay short and dense).
- **Keep the page furniture the same.** Hands-on steps are normal page
  content, not boxes: a short `###` subsection (for example "See it in your
  playground") with one sentence saying what to do, the command, the real
  output, and one or two sentences saying what it shows. A `> [!TIP]` box is
  only for a genuinely useful tip (a habit, a shortcut, how to spot a
  problem), never for a command snippet, and never two in a row. Each part ends with a
  `## Common pitfalls` `> [!WARNING]` block for that part only. Use a Mermaid
  diagram for a flow, an order or a state change, keep it under about 12
  boxes, and follow it with one sentence that says what it shows.
- **Mermaid without HTML.** The platform renders Mermaid with HTML labels
  switched off, so `<br/>` and any other HTML tag break the drawing. Rules:
  - One line per box, no `<br/>`, no HTML. Keep the box to the thing's name
    (`"scout-v2"`, `"istiod"`, `"Service: scout"`).
  - Put the logic on the arrows: `E -->|"version: v2"| P2`,
    `I -->|"CDS"| C`, `A -->|"end-user: jason"| B`. Keep edge labels short.
  - Quote every label. Prefer `flowchart TB`; use `LR` only for a short chain.
  - Sequence diagrams: short participant aliases (`participant S as shuttle`)
    and short message text.
  - Anything longer (cluster names, full hostnames) goes in the sentence under
    the diagram.
- **No links to outside sources.** Course pages, labs and playground docs do
  not link to or point at outside websites (official docs, GitHub, blogs,
  RFCs), and they have no "Reference" or "Official docs" lists. Everything the
  reader needs is explained on the page itself. Not affected: addresses the
  reader actually uses in a command or browser (`http://127.0.0.1:9080`,
  `curl https://httpbin.org`), and the Mission Briefing's contributors and
  "report a mistake" links.
- **Configuration goes to a file first.** Whenever the reader should apply
  YAML (course parts, playground docs, labs), use three separate steps:
  1. "Save this as `virtualservice-scout.yaml`:" followed by a plain
     ` ```yaml ` block with only the YAML. No `cat > file <<'EOF'`, no
     `kubectl apply -f - <<EOF`, no shell around it.
  2. "Apply it:" followed by a ` ```sh ` block with only
     `kubectl apply -f virtualservice-scout.yaml`.
  3. "Then check the result:" followed by the check commands, if any.
  The file name says the kind and the object. If a value must come from the
  reader's cluster (an IP address), use a placeholder like `<PARTNER>` in the
  YAML and say how to get the value (`echo $PARTNER`); never put shell
  variables inside YAML. Apply an object the first time its YAML appears; do
  not show it once "to read" and paste it again later. Never tell the reader
  to apply something from the playground's `examples/` folder: they start the
  playground with `astrona run`, so that folder is not on their machine.
- **Helpers have readable names.** Shell helper functions and variables use
  names that say what they do (`check_route`, `count_versions`,
  `$SERVICE_URL`), never single letters.

## About this repo (ATS014 only)

Everything above is general and can be copied to other course repositories. This
section is only true for this one.

### What the student is trying to learn

- **The goal:** pass the **Traffic Management** domain of the **Istio
  Certified Associate (ICA)** exam. It is 35% of the exam, the biggest single
  part.
- **What the exam really tests:** writing Istio configuration by hand, on a live
  cluster, under time pressure, and proving it works. So the student must
  *do* things (route, split, retry, expose, lock down), not just recognise
  words. Every explanation should lead to something they can run.
- **The seven exam topics:** ingress and egress traffic, routing inside the
  mesh, traffic policies with destination rules, traffic shifting, connecting
  to external workloads and services, resilience (timeouts, retries, circuit
  breaking, outlier detection, failover), and fault injection.
- **The version:** everything is built and checked on **Istio 1.30.5**
  on a `kind` cluster. Bookinfo playgrounds install it with Helm; the older
  playgrounds and the graded labs use the `demo` profile. Do not teach fields
  or behaviour from other versions without saying so.
- **The main source:** the Istio concepts page,
  <https://istio.io/latest/docs/concepts/traffic-management/>. Sections are
  named after the exam topics; check every page against the concepts page and
  the API reference.
- **The sample app:** the playgrounds run **the Starfleet**: the Istio docs'
  Bookinfo sample with space names (`scout` v1, v2 and v3 instead of
  `reviews`; see the fleet table below). Playgrounds not renamed yet still use
  the Bookinfo names, and the graded labs still use `notification-service`.

### Space analogy glossary

Use these pictures for these terms, in every course page, lab and playground.
Keep them consistent so the astronaut builds one picture of the universe.

**The universe**

| Term | Space picture |
| --- | --- |
| The learner | An astronaut (a cadet on their first missions) |
| Kubernetes cluster | A solar system |
| Namespace | A planet in that solar system |
| Pod | A spaceship |
| Container | A module inside the ship (the app is the crew) |
| Kubernetes Service | A beacon: one call sign that a whole group of ships answers to |
| Request / response | A signal sent out, and the reply signal |
| Port | A radio channel |
| Service mesh | The fleet's shared signal network |
| `kind` cluster on your laptop | A training solar system in the simulator |

**The mesh**

| Term | Space picture |
| --- | --- |
| Sidecar proxy (Envoy) | The ship's communications officer: every signal in or out goes through them |
| Sidecar injection | Putting a communications officer on board when the ship launches (ships already flying do not get one) |
| `istiod` (control plane) | Mission control: it sends every communications officer their orders |
| xDS push | Mission control radioing new orders to every ship in flight, no landing needed (no restart) |
| Service registry | The star chart: every planet and beacon mission control knows about |
| mTLS | A secret handshake both ships check before they talk |

**Steering signals**

| Term | Space picture |
| --- | --- |
| VirtualService | The flight plan: which way a signal flies, based on what it carries |
| Routing rules / precedence | The flight plan's checklist, read top to bottom; the first line that fits is used |
| `match` (header, path, query) | Reading the signal's label before deciding where it goes |
| DestinationRule | Docking instructions for one beacon: which ship classes exist and how to approach |
| Subset (v1, v2, v3) | Ship classes of the same model: same call sign, different build |
| Weighted routing / canary | Sending a small share of signals to the new ship class before the whole fleet switches |
| Mirroring | Sending a copy of each signal to a test ship; its replies are ignored |
| Load balancing | Deciding which ship in a squadron takes the next signal |
| Session affinity | Making the same astronaut always reach the same ship |
| Consistent hash ring | The rings of Saturn: each signal lands at one point on the ring, and the next ship along the ring takes it |
| Rewrite / redirect | Re-addressing a signal in flight / telling the sender "try that other frequency" |

**The borders of the solar system**

| Term | Space picture |
| --- | --- |
| Ingress gateway | The spaceport arrival gate: the one door signals from outside the solar system come through |
| Egress gateway | The departure gate: all signals leaving the solar system go out one checked exit |
| ServiceEntry | Adding a planet from another solar system to the star chart |
| `ALLOW_ANY` / PassthroughCluster | Ships may signal any planet, charted or not |
| `REGISTRY_ONLY` / BlackHoleCluster | "Signal only charted planets"; anything else falls into a black hole |
| Sidecar resource | Giving a ship a smaller star chart with only the planets it needs |
| WorkloadEntry | Adding an old ship that flies outside the fleet network to the star chart |

**When things go wrong**

| Term | Space picture |
| --- | --- |
| Timeout | The abort window: no reply by then, the signal is given up |
| Retries | Re-sending a signal that got lost in space |
| Circuit breaker | Raising the shields (closing the hatch) on an overloaded ship before the overload spreads |
| Outlier detection | Pulling a damaged ship out of formation for a while |
| Locality failover | Switching to a ship orbiting another planet when the nearest one is down |
| Fault injection | A simulation drill: fake delays and failures to train the crew |
| Single point of failure | The Death Star: huge and powerful, but one weak spot takes it all down |
| Access log / response flags | The ship's black box flight log, with short codes for what went wrong |

**The playground fleet: the Starfleet**

The playgrounds run the Istio Bookinfo sample with **space names**. The images
are the official Bookinfo images; only the Kubernetes names change. Use these
names everywhere (commands, YAML, prose). Never call it a "book review" app.

| Space name (Kubernetes name) | Was in Bookinfo | Role |
| --- | --- | --- |
| `starfleet` (namespace) | `bookinfo` | The planet the fleet lives on |
| `bridge` | `productpage` | The flagship command deck: the page astronauts see; it signals the other ships |
| `cargo` | `details` | The supply ship: answers with facts about an item |
| `scout` v1/v2/v3 | `reviews` | Three ship classes of one scout: v1 no stars, v2 black stars, v3 red stars |
| `navcom` | `ratings` | The navigation computer the v2 and v3 scouts ask for the star rating |
| `shuttle` | `curl` | Your test client: every test signal is sent from here |
| `probe` v1/v2 | `httpbin` | The echo probe: sends back exactly what it receives |
| `fortio` | `fortio` | The load generator: a swarm of signals fired at once |
| `jason` | `jason` | A fellow astronaut; logged in on the bridge, his signals carry `end-user: jason` |

Built into the images and **unchanged**: the URL paths `/productpage`,
`/details/0`, `/reviews/0`, `/ratings/0`, and the probe's `/headers`,
`/status/...`, `/delay/...`. So a signal to the scout is
`http://scout:9080/reviews/0`. The fleet manifest is
`bootstrap/manifests/starfleet.yaml` in each renamed playground.

Rename status (playground + module text):
- Renamed and checked on a cluster: 010-01.
- Renamed, partly checked: 020-01 (part 3 scaling step and practice task not re-run).
- Renamed, not yet checked on a cluster: 010-03, 020-02.
- Not renamed yet: 030-01, 040-01, 040-02, 040-03, 050-01, 060-01, 070-01, 080-01.
- Test clusters on the maintainer's machine: one at a time (it also runs the
  platform stack; parallel clusters ran it out of memory).

### Where things are in this repo

| What | Where |
| --- | --- |
| Course outline the platform reads: every reading page and lab, in order. Never list `solution.md` here | `astrona.yaml` |
| Overview, curriculum table, how to run things | `README.md` |
| Mission Briefing: course intro, setup, how the course is made, maintainers, how to report mistakes (first in `astrona.yaml`) | `sections/intro/` |
| Module reading: landing page plus deep-dive parts | `sections/section-0N0/module-0M/course*.md` |
| Graded lab: task, walkthrough, setup, grader | `.../labs/lab-0N/` (`question.md`, `solution.md`, `bootstrap/`, `validation/`) |
| Ungraded sandbox for a module | `.../playground/` (`docs/overview.md` says what is in the box) |
| One graded integration lab per section | `sections/section-0N0/capstone/labs/lab-01/` |

Work in progress: playgrounds are moving to Bookinfo. Moved so far: 010-01,
010-03, 020-01, 020-02, 030-01, 040-01, 040-02, 040-03, 050-01, 060-01,
070-01, 080-01. The graded labs and capstones still use their own small apps
(`notification-service` and similar), so say so when a reading page points
at them.

### Running things

```bash
# Playground (ungraded)
astrona run --git ssh://git@github.com/astrona-io/ATS014.git -c sections/section-010/module-01/playground
astrona destroy ats-014-playground-010-01   # takes metadata.name from config.yaml, not the path

# Lab or capstone (graded against the live cluster)
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-010/module-01/labs/lab-01
astrona submit -c sections/section-010/module-01/labs/lab-01
```

Graders check **behaviour** (send real traffic, read the proxy's configuration),
not just that an object exists. A lab's `question.md` and `solution.md` must
match what its `validation/` scripts actually check.

### Where to find trusted sources

Check facts here before writing them down. Prefer these over memory.

- **Concepts (the course spine):**
  <https://istio.io/latest/docs/concepts/traffic-management/>
- **API reference, one page per object:**
  [VirtualService](https://istio.io/latest/docs/reference/config/networking/virtual-service/),
  [DestinationRule](https://istio.io/latest/docs/reference/config/networking/destination-rule/),
  [Gateway](https://istio.io/latest/docs/reference/config/networking/gateway/),
  [ServiceEntry](https://istio.io/latest/docs/reference/config/networking/service-entry/),
  [Sidecar](https://istio.io/latest/docs/reference/config/networking/sidecar/),
  [WorkloadEntry](https://istio.io/latest/docs/reference/config/networking/workload-entry/)
- **Hands-on tasks** (the docs' own step-by-step versions of most modules):
  <https://istio.io/latest/docs/tasks/traffic-management/>, for example
  request routing, traffic shifting, mirroring, request timeouts, fault
  injection, circuit breaking, ingress, egress and locality load balancing.
- **Bookinfo:** <https://istio.io/latest/docs/examples/bookinfo/>. Its YAML
  ships in the Istio release under `samples/bookinfo/`.
- **Debugging and proof:**
  [proxy-config and proxy-status](https://istio.io/latest/docs/ops/diagnostic-tools/proxy-cmd/),
  [istioctl analyze messages](https://istio.io/latest/docs/reference/config/analysis/),
  [protocol selection](https://istio.io/latest/docs/ops/configuration/traffic-management/protocol-selection/),
  [access logs](https://istio.io/latest/docs/tasks/observability/logs/access-log/)
- **The exam itself:** the ICA page on the Linux Foundation / CNCF training
  site lists the official curriculum. The topic list above comes from this
  repository's README and has not been re-checked against it.

### Skills to use here

The `astrona-course-*` skills do most authoring jobs in this repository: planning
(`domain-plan`), creating the tree (`domain-scaffold`), building modules
(`domain-build`), deep-dive parts (`deep-dive`), labs and playgrounds (`lab`),
lab docs (`lab-docs`), challenges (`create-challenge`), quizzes
(`generate-assessment`) and fact-checking (`review-accuracy`).
