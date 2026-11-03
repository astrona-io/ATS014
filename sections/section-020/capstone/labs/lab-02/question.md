# Question

Solve this question on: `terminal`

The `probe` service is released in a new version. Web clients reach it through the Service `probe` over HTTP. A second group of clients reaches the same pods through the Service `probe-tcp`, which Istio treats as plain TCP. Both groups must see a gradual release, and the release team wants a shadow copy of the web traffic.

The namespace `starfleet` runs:

* `probe-v1` and `probe-v2`: the `probe` HTTP echo server in two versions, pods labelled `version: v1` and `version: v2`. The path `/hostname` returns the name of the pod that handled the request.
* `probe`: a Service on port `8000` whose port is named `http`, selecting both versions.
* `probe-tcp`: a Service on port `8000` whose port is named `tcp`, selecting the same pods.
* `probe-shadow`: a separate Deployment and Service on port `8000`. Its pods are not selected by `probe` or `probe-tcp`.
* `shuttle`: a client pod with `curl`.

Istio is installed and every pod has a sidecar proxy. There is no `DestinationRule` and no `VirtualService`. Create the objects so that:

1.  A `DestinationRule` for the host `probe` and a `DestinationRule` for the host `probe-tcp` each define the subsets **`v1`** and **`v2`**, selecting on the pods' **`version`** label.
2.  There is exactly one `VirtualService` for the host `probe`. A request with the header **`x-tester: yes`** goes to subset `v2` only. Every other request goes to `v1` (weight **80**) or `v2` (weight **20**).
3.  The same rule that holds the 80/20 split mirrors **100%** of its requests to the host **`probe-shadow`**. The header rule does not need to mirror.
4.  There is exactly one `VirtualService` for the host `probe-tcp`. It has a `tcp` route that matches port **`8000`** and sends **70** to subset `v1` and **30** to subset `v2`.
5.  The proxy of `shuttle` holds the mirror policy for `outbound|8000||probe-shadow.starfleet.svc.cluster.local` in its route table, and weighted clusters for the two `probe-tcp` subsets in its listener for port `8000`.
6.  HTTP behaves per request. The grader sends 20 requests with `x-tester: yes`, and all must be answered by `probe-v2`. It sends 150 requests without the header: between 15 and 45 must come from `probe-v2`, all the others from `probe-v1`, and none from `probe-shadow`. At least 135 copies must reach `probe-shadow`. It also sends 60 requests over one connection to `probe`, and both versions must answer.
7.  TCP behaves per connection. The grader sends 15 requests over one connection to `probe-tcp`, five times, and each run must be answered by a single pod. It opens 150 fresh connections to `probe-tcp`: between 25 and 65 must come from `probe-v2`, and the others from `probe-v1`.
8.  Leave the Deployments, the pod labels and the Services unchanged, and do not add or remove workloads.

A mirror and a weighted split on the same `http` rule are independent: the mirror never takes part in the split. A `tcp` route has no mirror.
