# Question

Solve this question on: `terminal`

A weighted `tcp` route should send 80% of the connections to the stable version of the `probe` and 20% to the new version. The split never happens: the answers ignore the weights, and some connections may fail. Nobody has noticed, because the `VirtualService` looks correct and connections still work.

The namespace `starfleet` runs:

* `probe-v1` and `probe-v2`: the `probe` HTTP echo server in two versions, pods labelled `version: v1` and `version: v2`. The path `/hostname` returns the name of the pod that handled the request.
* `probe`: a Service on port `8000` whose port is named `http`. It is not part of the problem.
* `probe-tcp`: a second Service on port `8000` (container port `8080`) that selects both versions.
* `shuttle`: a client pod with `curl`.

Istio is installed and every pod has a sidecar proxy. A `VirtualService` named `probe-tcp` has one `tcp` route that matches port `8000` and sends 80 to subset `v1` and 20 to subset `v2`. A `DestinationRule` named `probe-tcp` defines the subsets. The `VirtualService` is correct.

Find out why the split never happens, and fix it so that:

1.  The port of the Service `probe-tcp` is named **`tcp`**, with the port number `8000` and the container port `8080` unchanged.
2.  The `DestinationRule` `probe-tcp` defines the subsets **`v1`** and **`v2`**, each selecting on the pods' **`version`** label, so that each subset selects its own pods.
3.  There is still exactly one `VirtualService` for `probe-tcp`, and its `tcp` route still matches port `8000` and weighs 80 for `v1` and 20 for `v2`.
4.  The proxy of `shuttle` holds the weighted clusters in its listener for port `8000`, and the cluster `outbound|8000|v2|probe-tcp.starfleet.svc.cluster.local` has at least one healthy endpoint.
5.  The split is real. The grader opens 150 fresh connections to `http://probe-tcp:8000/hostname`. Every connection must get an answer, and between 15 and 45 answers must come from `probe-v2`.
6.  Leave the Deployments, the pod labels, the Service `probe` and the `VirtualService` unchanged, and do not add or remove workloads.

There is more than one cause. The route table and the listener of the proxy of `shuttle` tell you whether the proxy treats the route as TCP. The endpoints of the cluster tell you whether a subset has pods.

The lab saves its starting state in the files `service-probe-tcp.yaml`, `destinationrule-probe-tcp.yaml` and `virtualservice-probe-tcp.yaml` in its `resources` folder, and two helper scripts: `count-connections.sh` opens a new connection per sample, and `count-reused.sh` sends all samples over one connection. `astrona res` lists and runs them.
