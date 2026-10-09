# Question

Solve this question on: `terminal`

The release candidate of the `probe` should receive a copy of every request, and it receives nothing. The clients get correct responses, so nobody has noticed.

The namespace `starfleet` runs:

* `probe-v1`: the stable version of the `probe` HTTP echo server, pods labelled `version: v1`.
* `probe-v2`: the release candidate, pods labelled `version: v2`.
* `probe`: one Service on port `8000` that selects on the `app` label only. The path `/hostname` returns the name of the pod that handled the request.
* `shuttle`: a client pod with `curl`.

Istio is installed and every pod has a sidecar proxy. A `VirtualService` named `probe` routes every request to the subset `v1` and mirrors every request to the subset `v2`. A `DestinationRule` named `probe` defines the subsets. Clients get correct responses, but `probe-v2` never receives a copy.

Find out why the mirror sends nothing, and fix it so that:

1.  The `DestinationRule` named `probe` defines the subsets **`v1`** and **`v2`**, each selecting on the pods' **`version`** label, so that each subset selects its own pods.
2.  The mirror cluster `outbound|8000|v2|probe.starfleet.svc.cluster.local` has at least one healthy endpoint in the proxy of `shuttle`.
3.  There is still exactly one `VirtualService` for `probe`. Its first `http` rule routes every request to subset `v1` only, and mirrors to subset `v2` at **100%**.
4.  Every response that `shuttle` gets comes from `probe-v1`. The grader sends 30 requests to `http://probe:8000/hostname` and fails if any response comes from another version.
5.  `probe-v2` really receives the copies. The grader sends 20 more requests and counts the `GET /hostname` lines in the application log of `probe-v2`. At least 18 must arrive.
6.  Leave the Deployments, the pod labels and the Service unchanged, and do not add or remove workloads.

The client's responses cannot tell you whether the mirror works. Find the proof on the receiving side, and in the proxy of `shuttle`.
