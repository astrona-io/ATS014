# Writing style for this repo

All study text here (course pages, lab docs, READMEs, comments in YAML and
scripts) is for people learning a technical subject, often for a
certification exam. Many of them are not native English speakers and have no
university degree.

## Technical documentation in plain English

This is technical documentation. Say exactly what the system does, with the
real technical terms, in clear and simple English. Never hide a concept
behind a metaphor, a made-up name or a vague word: the reader must learn the
words they will meet in the product, the logs and the exam.

Strict guidelines:

1. Use the correct technical term every time (request, response, pod,
   namespace, Service, sidecar proxy, certificate, mTLS, JWT, listener). The
   first time a term appears in a file, define it in one plain sentence that
   says what it is and what it does. Spell out every acronym on first use.
2. No metaphors or analogies in explanations. Not "the communications
   officer", but "the sidecar proxy (Envoy)"; not "a signal", but "a
   request"; not "the planet", but "the namespace".
3. Simple sentences. Target a Flesch-Kincaid Grade Level of 8 or 9 for the
   prose around the terms. Keep sentences direct; split long sentences into
   two. No corporate buzzwords.
4. Use short paragraphs (max 3-4 sentences per paragraph).
5. Use the active voice ("istiod sends the configuration", not "the
   configuration is sent").

## How this applies to course material

- **Know which file you are in.** A module has a short landing page, a few
  deep-dive parts and a summary page. The landing page is a map: goals, what
  to know first, the order of the parts. The real teaching goes in the parts.
  The summary closes the module. A lab
  has a task, a step-by-step solution and a short intro. Keep each file to its
  job. Do not add "Prerequisite: ... Next: ..." navigation lines to pages;
  the landing page and the course outline already give the order.
- **Keep each part short.** One idea per part, about 5 to 8 minutes of
  reading and at most about 8 command blocks, so a learner can finish it with
  the playground in one sitting of about 15 minutes. Split at a natural seam
  where each half ends with something the learner has seen work. Never split
  only to hit a number. When you split, renumber the files, fix every "Part N"
  reference in the module and `astrona.yaml`.
- **Read like a book, not like a web page.** Each part reads as a chapter of
  a technical book. Open with a short paragraph on the problem it solves and
  why it matters. Link each paragraph to the next with a transition sentence.
  Close with a paragraph that sums up what the reader now knows and the
  question still open, before `## Common pitfalls` and the mission. Write
  explanations as prose; keep bullets for real lists (fields, ordered steps,
  options). Use `##` only when the topic changes and `###` only inside a long
  section, never for a single command. Weave hands-on steps into the text:
  one or two sentences on what to run and why, the command, the real output,
  then a sentence or two on what it shows.
- **The module ends with a summary.** The last page of every module is
  `course-0N-summary.md` with the title `# Summary`: a few short prose
  paragraphs on what the reader learned, organised by idea, optionally with
  one short list of key facts. It names no parts, modules, sections or
  chapters, and has no links, lab table, quiz or commands. Its last line is
  `<!-- astrona:playground:destroy -->` on its own line; the platform turns it
  into the step that removes the playground.
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
  need the `scout` `DestinationRule` applied"). This includes the summary.
  The landing page does not have a "Where this fits" section.
- **Write words out in full.** Do not use informal short forms in prose:
  write "communications", "configuration", "repository", "administrator",
  "for example" and "that is", never "comms", "config", "repo", "admin",
  "e.g." or "i.e.". Names in code, commands and file paths stay as they are.
- **Exam terms stay.** The product's own names are what the reader must learn
  (for example a resource kind, a field, a command). Use them as they are and
  define each one in plain technical words the first time it appears in a
  file. Spell out acronyms on first use, with a short plain meaning.
- **The space theme is only for examples.** Space appears in two places and
  nowhere else: the names of the example workloads (the Starfleet: `bridge`,
  `scout`, `shuttle`, `probe`, the `starfleet` and `outpost` namespaces) and
  the short scenario that opens a lab task or a practice exercise (for
  example "the `drifter` in `outpost` must keep reaching the probe"). The
  explanation around an example is plain technical text: write "the
  `shuttle` pod sends a request to the `probe` Service", never "the shuttle
  sends a signal to the probe ship". Do not address the reader as an
  astronaut, and do not use space metaphors (communications officer, mission
  control, badge, airlock, guest list, star chart) for Istio or Kubernetes
  concepts. Titles of pages and labs name the technical task ("Require mTLS
  With PeerAuthentication"), not a space story.
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
- **Keep the page furniture the same.** Hands-on steps are part of the prose
  (see "Read like a book"), not boxes or headings of their own. A `> [!TIP]` box is
  only for a real tip: advice the reader can reuse beyond this one step (a
  habit, a shortcut, how to spot a problem, an exam habit). Everything else
  is a normal sentence: notes about the current step ("if the log line is
  old, run it again"), background facts, optional extra steps, and plain
  information. Never a command snippet, never two in a row, and most pages
  need zero or one tip. Each part ends with a
  `## Common pitfalls` `> [!WARNING]` block for that part only. Use a Mermaid
  diagram for a flow, an order or a state change, keep it under about 12
  boxes, and follow it with one sentence that says what it shows.
- **Labs come right after the part they practise.** Do not collect all
  graded labs at the end of a module. In `astrona.yaml`, put each lab (its
  `question.md` reading and the `lab` entry) right after the reading part it
  tests. If a part teaches a gradeable skill and no lab covers it, create a
  new lab. That part then ends with a `## Your mission: <lab title>` section:
  one sentence on what the reader can now do, one on what the mission asks,
  then pause the playground (`astrona stop <playground name>`), the
  `astrona run` and `astrona submit` commands, and finally
  `astrona destroy <lab name>` plus `astrona start <playground name>`.
- **Renew the playground before hands-on work.** Every reading part that
  runs commands has `<!-- astrona:playground:renew -->` exactly once, on its
  own line, right before the first hands-on step (the first "Save this as"
  or the first command block), so the playground timer is reset before the
  learner needs the playground. Not on landing pages (they carry
  `<!-- astrona:playground -->`), summary pages (they carry
  `<!-- astrona:playground:destroy -->`) or pages without commands.
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
- **Every course starts with an Introduction.** It lives in `sections/intro/`
  and is the first entry in `astrona.yaml` (`id: module-intro`, title
  "Introduction"). It has exactly these four pages, in this order:
  - `README.md`, `# Introduction`: what the introduction covers and its three
    pages, named in prose (no links), ending with the topic the course starts
    with.
  - `course-01-welcome.md`, `# Welcome To The Course`: who the course is for,
    the exam domain and what the reader can do at the end, the words the
    course uses, the example app, how the course is laid out and how to read
    a page.
  - `course-02-get-your-machine-ready.md`, `# Get Your Machine Ready`: the
    tools to install, the `astrona` commands used every day, and what to do
    when a start goes wrong.
  - `course-03-how-this-course-is-made.md`, `# How This Course Is Made`: how
    content is written and checked, the maintainers, how to report a mistake,
    and the license.
  The Introduction teaches no product content and has no playground, labs or
  summary. Its only links are the repository's contributors page, issues
  page and license.
- **No links to other course files.** A course page (every reading listed in
  `astrona.yaml`, the playground guide `docs/overview.md`, and a lab's
  `question.md` and `solution.md`) never links to or points the reader at
  another page or file of the repository: no links to parts, summaries,
  labs, `question.md`, other modules, sections or the Introduction, and no
  "see `practice.md`" or "open `config.yaml`". The platform shows the pages in
  the order of `astrona.yaml`, so a link only adds a second, often wrong,
  path. Name a thing in plain words when the reader needs it ("the task is on
  the next page"), and state a fact on the page itself instead of sending the
  reader somewhere else. Repository files for authors (the root `README.md`,
  a lab's or playground's `README.md`) may link.
- **No links to outside sources.** Course pages, labs and playground docs do
  not link to or point at outside websites (the one exception is the
  `resources` field of a lab entry in `astrona.yaml`) (official docs, GitHub, blogs,
  RFCs), and they have no "Reference" or "Official docs" lists. Everything the
  reader needs is explained on the page itself. Not affected: addresses the
  reader actually uses in a command or browser (`http://127.0.0.1:9080`,
  `curl https://httpbin.org`), and the Introduction's contributors and
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
- **What the exam really tests:** writing Istio traffic configuration by
  hand, on a live cluster, under time pressure, and proving it works. So the
  student must *do* things (route, split, retry, expose, lock down), not just
  recognise words. Every explanation should lead to something they can run,
  and every rule should be proved with real requests (which version answered,
  which status code came back, what the proxy's configuration says).
- **The seven exam topics (curriculum items):** configuring ingress and
  egress traffic, configuring routing within a service mesh, defining traffic
  policies with destination rules, configuring traffic shifting, connecting
  in-mesh workloads to external workloads and services, using resilience
  features (circuit breaking, failover, outlier detection, timeouts,
  retries), and using fault injection. The course order is not the exam
  order, and ingress and egress are two sections (060 and 080). The README
  table maps each section to its exam topic.
- **The sections:**

  | Section | Title | Exam topic |
  | --- | --- | --- |
  | 000 | Mesh Foundations | None: the basics every other section needs |
  | 010 | Configuring Routing Within A Service Mesh | Routing |
  | 020 | Configuring Traffic Shifting | Traffic shifting |
  | 030 | Defining Traffic Policies With Destination Rules | Destination rules |
  | 040 | Using Resilience Features (Circuit Breaking, Failover, Outlier Detection, Timeouts, Retries) | Resilience |
  | 050 | Using Fault Injection | Fault injection |
  | 060 | Configuring Ingress And Egress Traffic — Ingress | Ingress and egress |
  | 070 | Connecting In-Mesh Workloads To External Workloads And Services | External workloads and services |
  | 080 | Configuring Ingress And Egress Traffic — Egress | Ingress and egress |

- **The version:** everything is built and checked on **Istio 1.30.5** on a
  single-node `kind` cluster. Playgrounds install it with Helm; about half the graded
  labs and all capstones still use `istioctl install --set profile=demo`
  (see "Environment facts" below). Do not teach fields or behaviour from
  other versions without saying so.
- **The main sources:** the Istio traffic management concepts page,
  <https://istio.io/latest/docs/concepts/traffic-management/>, and the API
  reference for each networking object. Check every page against them.

### Terms, not metaphors

Explanations use Istio's and Kubernetes' own words. Define each one in plain
technical language on first use in a file, for example:

| Term | First-use definition (example wording) |
| --- | --- |
| Sidecar proxy (Envoy) | A proxy container Istio adds to each pod; all inbound and outbound traffic of the pod passes through it |
| `istiod` | Istio's control plane; it turns the cluster's Services and Istio objects into proxy configuration and sends it to every proxy |
| xDS | The protocol `istiod` uses to push configuration to proxies while they run (listeners, routes, clusters, endpoints) |
| Service registry | The list of hosts and endpoints `istiod` knows about: Kubernetes Services plus `ServiceEntry` and `WorkloadEntry` objects |
| `VirtualService` | Sets how requests to a host are routed: match rules, read top to bottom, and the destinations, weights, timeouts, retries and faults for each |
| `DestinationRule` | Sets what happens after routing picks a host: subsets, load balancing, connection pool limits, outlier detection and TLS to the upstream |
| Subset | A named group of a Service's pods, selected by labels (for example `version: v2`) |
| Weighted routing | Splitting requests between destinations by percentage, for example 90% to v1 and 10% to v2 |
| Mirroring | Sending a copy of each request to a second destination; the copy's response is thrown away |
| Circuit breaking | Connection pool limits in a `DestinationRule`; requests over the limit fail at once with `503` and the `UO` flag |
| Outlier detection | Removing an endpoint from the load balancing pool for a while after it returns too many errors |
| Locality failover | Preferring endpoints in the caller's own region and zone, and moving to another locality when they fail |
| Fault injection | A `VirtualService` setting that makes the proxy add a delay or return an error, to test how callers react |
| Ingress gateway | An Envoy proxy at the edge of the mesh that accepts traffic from outside the cluster |
| Egress gateway | An Envoy proxy that outbound traffic to outside hosts can be sent through, so it leaves the mesh at one point |
| `ServiceEntry` | Adds a host outside the mesh (or a non-Kubernetes workload) to the service registry |
| `outboundTrafficPolicy` | Mesh setting: `ALLOW_ANY` lets unknown hosts through (`PassthroughCluster`); `REGISTRY_ONLY` blocks them (`BlackHoleCluster`) |
| `Sidecar` resource | Limits which hosts and ports one workload's sidecar proxy gets configuration for |
| `WorkloadEntry` | Describes one workload that does not run in Kubernetes (for example a virtual machine), so the mesh can route to it |
| Response flags | Short codes in the Envoy access log that say why a request failed (`NR`, `NC`, `UH`, `UO`, `UT`) |

Older pages still use space metaphors (communications officer, signal,
mission control, star chart, beacon, docking instructions, black hole). The
root `README.md` and the section READMEs still do too. Replace them with the
real terms when you touch a page.

### The example workloads: the Starfleet

The playgrounds and course pages run the Istio Bookinfo sample with **space
names**. The images are the official Bookinfo images; only the Kubernetes
names change. Use these names in commands, YAML and example text. The names
are the only space element: describe what each workload does in technical
terms. Never call it a "book review" app.

| Kubernetes name | Was in Bookinfo | Service account | What it is |
| --- | --- | --- | --- |
| `starfleet` (namespace) | `bookinfo` | | Namespace for the sample app, sidecar injection on |
| `bridge` | `productpage` | `starfleet-bridge` | Web frontend (`/productpage`) on port `9080`; calls `cargo` and `scout` |
| `cargo` | `details` | `starfleet-cargo` | Backend that returns item details |
| `scout` v1/v2/v3 | `reviews` | `starfleet-scout` | Backend in three versions: v1 no stars, v2 black stars, v3 red stars |
| `navcom` | `ratings` | `starfleet-navcom` | Backend that `scout` v2 and v3 call for the star rating |
| `shuttle` | `curl` | `shuttle` | Test client pod in the mesh; test requests are sent from here |
| `probe` v1/v2 | `httpbin` | `probe` | HTTP echo server (go-httpbin); Service port `8000`, container port `8080` |
| `fortio` | `fortio` | `default` | Load generator; sends many requests at once (circuit breaking, retries) |
| `outpost` (namespace) | `legacy` | | Namespace with sidecar injection **off**, on purpose |
| `drifter` (in `outpost`) | `legacy/curl` | `default` | Client pod with no sidecar; its requests never pass through a proxy |
| `jason` | `jason` | | Example end user; after login on the bridge, its requests carry `end-user: jason` |

A few modules add workloads of their own. Describe them in technical terms
in the module that uses them:

- `probe-zone-a`, `probe-zone-b` and `probe-zone-a-damaged` (section 040,
  locality and outlier detection): `probe` pods that set their locality with
  the `istio-locality` label, because `kind` has no real zones.
- `partner`, `relay` and `rogue` in `outpost` (sections 070 and 080): pods
  outside the mesh that stand in for external hosts, so the labs need no
  internet access. In section 080 module 02, `partner` is an nginx server
  that only accepts TLS with a client certificate.
- `freighter` (section 070 module 03): the service account and
  `WorkloadEntry` names (`freighter-vm-1`, `freighter-vm-2`) for the
  workload that runs outside Kubernetes.
- `patrol` (section 010 module 03 lab 01): an extra client with its own
  service account.

Built into the images and **unchanged**: the URL paths `/productpage`,
`/details/0`, `/reviews/0`, `/ratings/0`, and the probe's `/headers`,
`/get`, `/status/...`, `/delay/...`. So a request to `scout` goes to
`http://scout:9080/reviews/0`, and a request to the probe goes to
`http://probe:8000/headers`. The manifests live in each playground's or
lab's `bootstrap/manifests/` (`starfleet.yaml`, `shuttle.yaml`, `probe.yaml`,
`namespace.yaml`, `access-logs.yaml`, and where needed `outpost.yaml`,
`fortio.yaml`, `probe-orbits.yaml`, `freighter.yaml`).

**Some graded labs keep their own small apps for now.** These run
`notification-service` and similar small apps, and their `question.md`
describes that app, so the learner is never confused: 010-01 lab-01 and
lab-02, 020-01 lab-01, 020-02 lab-01, 040-02 lab-01, 050-01 lab-01, 060-01,
060-02 and 060-03 lab-01, and the 020 and 050 capstones. New labs use the
Starfleet. When a reading page comes right before one of these labs, say in
one sentence that the lab uses a different app.

### Environment facts the text must respect

- **Playgrounds install Istio with Helm** (`istio-base` and `istiod`). A
  module that needs a gateway adds the `gateway` chart under its own release
  name: `istio-ingress` or `istio-ingressgateway` for ingress, `istio-egress`
  for egress. Use the Service name the module's playground really creates.
- **About half the graded labs and all capstones use `istioctl install --set
  profile=demo`.** The demo profile installs both an ingress gateway
  (`istio-ingressgateway`) and an egress gateway (`istio-egressgateway`) in
  `istio-system`. Either install method is fine while the lab passes
  `astrona test`.
- **No load balancer on `kind`.** A gateway Service's `EXTERNAL-IP` stays
  `<pending>`. Playgrounds reach the cluster through the `portForwards` in
  `config.yaml`: `bridge` on `127.0.0.1:9080`, and in the ingress modules the
  gateway on `127.0.0.1:8080` (HTTP) and `127.0.0.1:8443` (HTTPS). Labs use
  `kubectl port-forward`.
- **Locality without zones.** The single `kind` node has no region or zone
  labels, so locality failover pages set each pod's locality with the
  `istio-locality` label (`region.zone`, with dots). Say so when you teach
  locality.
- **Outbound internet.** Some egress and external service pages call
  `httpbin.org` (HTTP and HTTPS). These addresses are used in commands, so
  they are allowed on the page. Labs that grade egress use pods in `outpost`
  instead, so they do not depend on the internet.
- **Access logs are on.** Every playground applies `access-logs.yaml`, so
  `kubectl logs <pod> -c istio-proxy` shows one line per request with its
  response flags. Use this as proof.

### Where things are in this repo

| What | Where |
| --- | --- |
| Course outline the platform reads: every reading page and lab, in order. Never list `solution.md` here | `astrona.yaml` |
| Overview, sections table, how to run things | `README.md` |
| Introduction (see "Every course starts with an Introduction") | `sections/intro/` |
| Section overview and its modules | `sections/section-0N0/README.md` |
| Module reading: landing page, deep-dive parts, summary | `sections/section-0N0/module-0M/course.md`, `course-0N-*.md` |
| Graded lab: task, walkthrough, setup, grader | `.../labs/lab-0N/` (`question.md`, `solution.md`, `bootstrap/`, `solution/apply.sh`, `validation/`) |
| Ungraded sandbox for a module | `.../playground/` (`docs/overview.md` is the only learner page: what is in the box, helpers, and a final `## Practice tasks` section; `examples/` holds the authors' reference YAML) |
| One graded integration lab per section (not section 000) | `sections/section-0N0/capstone/labs/lab-01/` |

A lab folder holds:

| Path | Purpose |
| --- | --- |
| `config.yaml` | Lab definition; `metadata.docs` has `question: "question.md"` and `solution: "solution.md"` |
| `README.md` | Short intro with `estimated_duration` front matter and the run, submit and destroy commands |
| `question.md` | The exam-style task. Starts with `# Question` and `Solve this question on: \`terminal\`` |
| `solution.md` | Step-by-step walkthrough with real output |
| `bootstrap/` | Istio install, `bootstrap/manifests/` and the starting state, never the graded objects |
| `solution/apply.sh` | Reference end state, applied only by `astrona test` |
| `validation/validate-completed.sh` | Behavioural grading (sends real traffic) |

The platform reads the names in `metadata.docs` to show the task and the
solution. Never rename `question.md` or `solution.md`, even if a local
`astrona validate` complains about them.

### Lab metadata in `astrona.yaml`

`astrona.yaml` has one entry per section under `modules:` (`module-intro`,
`module-000`, `module-010` and so on up to `module-080`). Each section's
`content` lists, in order: the section `README.md`, then for each module its
landing page, its parts, and right after the part a lab tests, a `Question`
reading (`labs/lab-0N/question.md`) followed by the `type: lab` entry; the
module's summary page comes last. The section capstone closes the section.
Playgrounds are not listed: the landing page's `<!-- astrona:playground -->`
marker shows them.

Every `type: lab` entry (module labs and capstones) carries these fields, in
this order:

```yaml
      - type: reading
        title: Question
        path: sections/section-030/module-01/labs/lab-03/question.md
      - type: lab
        title: "Fix A Load Balancing Policy Lab"
        path: sections/section-030/module-01/labs/lab-03
        difficulty: beginner
        estimated_duration: 15m
        topic: destination-rules
        task_kind: troubleshooting
        tags: [destinationrule, load-balancing, consistent-hash, proxy-config]
        learning_goals:
          - Find why every request lands on one pod by reading the DestinationRule and the proxy's lbPolicy
          - Replace a consistentHash policy with ROUND_ROBIN and prove the spread with real requests
        resources:
          - name: "DestinationRule load balancer settings"
            url: https://istio.io/latest/docs/reference/config/networking/destination-rule/#LoadBalancerSettings
```

- `difficulty`: `beginner`, `intermediate` or `advanced`.
- `estimated_duration`: realistic time to solve it, for example `15m`, `30m`, `45m`.
- `topic`: exactly one of `foundations`, `routing`, `traffic-shifting`,
  `destination-rules`, `resilience`, `fault-injection`, `ingress-egress`,
  `external-services`.
- `task_kind`: exactly one of `build` (write the configuration from
  scratch), `troubleshooting` (find and fix what is broken) or `migration`
  (move a working setup to another API or layout, for example `Ingress` to
  the Gateway API). The platform filters labs by it, so it is a field of its
  own, never a tag.
- `tags`: 4 to 8 ids, only from the tag list below. Add a new tag to the list
  first if nothing fits.
- `learning_goals`: 2 or 3 plain sentences, each starting with a verb, saying
  what the learner proves in this lab.
- `resources`: 1 to 4 documentation pages, each with a `name` and a `url`
  that loads. This is the **only** place outside links are allowed: the
  platform shows them as optional further reading next to the lab.

**Tag list** (lower case, hyphens, never synonyms):

- Istio objects: `virtualservice`, `destinationrule`, `gateway`,
  `serviceentry`, `sidecar`, `workloadentry`, `workloadgroup`, `gateway-api`,
  `ingress-resource`, `peerauthentication`
- Routing: `header-matching`, `uri-matching`, `query-matching`, `rule-order`,
  `catch-all`, `subsets`, `short-hosts`, `fqdn`, `weighted-routing`,
  `canary`, `mirroring`, `rewrite`, `redirect`, `headers`, `cors`,
  `tcp-routing`, `tls-routing`, `protocol-selection`
- Traffic policy: `load-balancing`, `session-affinity`, `consistent-hash`,
  `connection-pool`, `circuit-breaking`, `outlier-detection`,
  `locality-failover`
- Resilience and testing: `timeouts`, `retries`, `fault-injection`, `delay`,
  `abort`
- Edge and outside: `ingress-gateway`, `allowed-routes`, `egress-gateway`,
  `tls-origination`, `tls-termination`, `registry-only`,
  `external-services`, `virtual-machines`, `sidecar-scoping`,
  `sidecar-injection`
- Failure signatures: `404-nr`, `503-nc`, `503-uh`, `503-uo`, `504-ut`,
  `ist0101`, `ist0130`, `ist0173`
- Tools: `proxy-config`, `proxy-status`, `istioctl-analyze`, `access-log`

### Running things

```bash
# Playground (ungraded)
astrona run --git ssh://git@github.com/astrona-io/ATS014.git -c sections/section-010/module-01/playground
astrona destroy ats-014-playground-010-01   # takes metadata.name from config.yaml, not the path

# Lab or capstone (graded against the live cluster)
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-010/module-01/labs/lab-01
astrona submit -c sections/section-010/module-01/labs/lab-01
astrona destroy ats-014-lab-010-01

# Authors: run a local, uncommitted copy, and prove a lab passes with its reference solution
astrona run -c sections/section-010/module-01/playground
astrona test -c sections/section-010/module-01/labs/lab-01
```

Names: a playground is `ats-014-playground-<section>-<module>` and a
capstone is `ats-014-capstone-<section>`. The first labs are
`ats-014-lab-<section>-<module>`; keep those names. A new lab takes
`ats-014-lab-<section>-<module>-<lab>`, for example `ats-014-lab-020-01-02`,
so two labs never share a name. Lab bootstrap scripts do not pin a kube
context: astrona sets `KUBECONFIG` for the lab, and `astrona test` runs on a
cluster with a different name. Every lab must pass `astrona validate` and
`astrona test`.

Graders check **behaviour** (send real traffic and count which version
answered, check the status code and the response flag, read the proxy's
configuration), not just that an object exists. A lab's `question.md` and
`solution.md` must match what its `validation/` scripts actually check.

Test clusters on the maintainer's machine: one at a time. Podman has 10 GiB
and also runs the platform stack; parallel clusters run it out of memory.
Never touch clusters you did not create (for example `istio-doc`).

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
  [WorkloadEntry](https://istio.io/latest/docs/reference/config/networking/workload-entry/),
  [WorkloadGroup](https://istio.io/latest/docs/reference/config/networking/workload-group/)
- **Hands-on tasks:** <https://istio.io/latest/docs/tasks/traffic-management/>,
  for example request routing, traffic shifting, mirroring, request timeouts,
  fault injection, circuit breaking, ingress (Istio `Gateway`, Kubernetes
  `Ingress` and the Gateway API), egress gateways, egress TLS origination and
  locality load balancing.
- **Bookinfo:** <https://istio.io/latest/docs/examples/bookinfo/>. Its YAML
  ships in the Istio release under `samples/bookinfo/`.
- **Debugging and proof:**
  [proxy-config and proxy-status](https://istio.io/latest/docs/ops/diagnostic-tools/proxy-cmd/),
  [istioctl analyze messages](https://istio.io/latest/docs/reference/config/analysis/),
  [protocol selection](https://istio.io/latest/docs/ops/configuration/traffic-management/protocol-selection/),
  [access logs](https://istio.io/latest/docs/tasks/observability/logs/access-log/)
- **The exam itself:** the ICA page on the Linux Foundation / CNCF training
  site lists the official curriculum. The domain weight (35%) and topic list
  above come from this repository's README and have not been re-checked
  against it.

### Skills to use here

The `astrona-course-*` skills do most authoring jobs in this repository: planning
(`domain-plan`), creating the tree (`domain-scaffold`), building modules
(`domain-build`), deep-dive parts (`deep-dive`), labs and playgrounds (`lab`),
lab docs (`lab-docs`), challenges (`create-challenge`), quizzes
(`generate-assessment`) and fact-checking (`review-accuracy`).
