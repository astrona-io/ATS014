# Question

Solve this question on: `terminal`

The `probe` service must move some connections to a new version, and its clients are not HTTP aware: they connect to the Service as plain TCP. The weights must apply per connection.

The namespace `starfleet` runs:

* `probe-v1` and `probe-v2`: the `probe` HTTP echo server in two versions, pods labelled `version: v1` and `version: v2`. The path `/hostname` returns the name of the pod that handled the request.
* `probe-tcp`: a Service on port `8000` (container port `8080`) that selects both versions. Its port is named `tcp`, so Istio treats it as plain TCP.
* `shuttle`: a client pod with `curl`.

Istio is installed and every pod has a sidecar proxy. There is no `DestinationRule` and no `VirtualService` for `probe-tcp`. Create them so that:

1.  A `DestinationRule` for the host `probe-tcp` defines the subsets **`v1`** and **`v2`**, each selecting on the pods' **`version`** label.
2.  There is exactly one `VirtualService` for the host `probe-tcp`. It has a `tcp` route that matches port **`8000`** and sends **80** to subset `v1` and **20** to subset `v2`.
3.  The proxy of `shuttle` holds the split: the listener for port `8000` has weighted clusters for `outbound|8000|v1|probe-tcp.starfleet.svc.cluster.local` and `outbound|8000|v2|probe-tcp.starfleet.svc.cluster.local`.
4.  One reused connection stays on one pod. The grader sends 15 requests over one connection, five times, and every one of those five runs must be answered by a single pod.
5.  The split is real. The grader opens 150 fresh connections to `http://probe-tcp:8000/hostname` and counts the answers. Between 15 and 45 of them must come from `probe-v2`, and all the others from `probe-v1`.
6.  Leave the Deployments, the pod labels and the Services unchanged, and do not add or remove workloads.

A single request tells you nothing about a weighted split. Count many connections, with one new connection for each sample.

The lab saves two helper scripts in its `resources` folder: `count-connections.sh` opens a new connection per sample, and `count-reused.sh` sends all samples over one connection. `astrona res` lists and runs them.
