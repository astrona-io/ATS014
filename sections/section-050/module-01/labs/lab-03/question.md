# Question

Solve this question on: `terminal`

A test that was never switched off is grounding the whole fleet. In the `starfleet` namespace, somebody injected an abort fault on `navcom` and forgot it. Limit the fault to test requests, without deleting it.

The `starfleet` namespace has sidecar injection switched on and runs these workloads:

* `scout`: a backend in three versions, v1, v2 and v3, on port `9080`. A `VirtualService` named `scout` sends **every** request to subset `v2`, which calls `navcom` for a star rating.
* `navcom`: a backend on port `9080`. A `DestinationRule` defines its subset `v1`.
* `shuttle`: a client pod with `curl`. Send your test requests from here.

The `VirtualService` named `navcom` aborts **every** request to `navcom` with `500`. Now every response from `http://scout:9080/reviews/0` says `"Ratings service is currently unavailable"` instead of showing star ratings. The `scout` application copies the `end-user` header of its incoming request onto its request to `navcom`.

The test team still wants the fault, but only for their own requests. Fix the `navcom` `VirtualService` so that:

1.  The `VirtualService` named `navcom` has **exactly two** `http` rules.
2.  The first rule matches the header `end-user` with the exact value **`tester`**, keeps the fault (abort with `500` for every matching request), and routes to subset `v1`.
3.  The second rule has no `match` and no `fault`, and routes to subset `v1`.
4.  A request from `shuttle` to `http://scout:9080/reviews/0` without the header gets star ratings again.
5.  The same request with `end-user: tester` still gets `"Ratings service is currently unavailable"`. A request with `end-user: tester` straight to `http://navcom:9080/ratings/0` gets a `500`, and the access log of `shuttle` marks it with the response flag **`FI`** (fault injected). A request without the header straight to `navcom` gets a `200`.
6.  The `scout` `VirtualService`, the Deployments and the Services stay unchanged.

The grader sends real requests from `shuttle`, reads the access log of `shuttle`, and checks the `navcom` `VirtualService`.
