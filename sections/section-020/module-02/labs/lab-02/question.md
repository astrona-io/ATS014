# Question

Solve this question on: `terminal`

Astronaut, a test ship should be hearing every signal, and it hears nothing. On the planet `starfleet`:

* `probe-v1` — the stable version of the echo probe, pods labelled `version: v1`
* `probe-v2` — the release candidate, pods labelled `version: v2`
* `probe` — one Service on port `8000` selecting on `app` only
* `shuttle` — your client pod with `curl`

Istio is installed and every pod is injected. A `VirtualService` named `probe` sends every signal to subset `v1` and mirrors every signal to subset `v2`. A `DestinationRule` named `probe` defines the subsets. The senders get correct answers, but `probe-v2` never receives a copy.

Find out why the shadow is quiet, and fix it so that:

1.  The `DestinationRule` named `probe` defines the subsets **`v1`** and **`v2`**, each selecting on the pods' **`version`** label, so that each subset selects its own pods.
2.  The mirror cluster `outbound|8000|v2|probe.starfleet.svc.cluster.local` has at least one healthy endpoint in the `shuttle`'s proxy.
3.  The `VirtualService` keeps its flight plan: every signal routed to subset `v1`, and mirrored to subset `v2` at **100%**.
4.  Every answer the `shuttle` receives comes from `probe-v1`. The grader sends 30 signals and fails if any answer comes from another version.
5.  `probe-v2` really receives the copies. The grader sends 20 more signals and counts the requests that arrive at `probe-v2`.
6.  Leave the Deployments, the pod labels and the Service unchanged, and do not add or remove workloads.

The sender's answers cannot tell you whether the mirror works. Find the proof on the receiving side, and in the `shuttle`'s proxy.
