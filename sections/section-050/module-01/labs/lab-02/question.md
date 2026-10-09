# Question

Solve this question on: `terminal`

The fleet must survive a slow navigation computer and a lost probe. In the `starfleet` namespace, inject one fault that makes `navcom` slow and one that makes `probe` look down.

The `starfleet` namespace has sidecar injection switched on and runs these workloads:

* `scout`: a backend in three versions, v1, v2 and v3, on port `9080`. A `VirtualService` named `scout` sends requests with the header `end-user: jason` to subset `v2` and every other request to subset `v1`. Only v2 and v3 call `navcom`.
* `navcom`: a backend on port `9080`. A `DestinationRule` defines its subset `v1`.
* `probe`: an HTTP echo server, v1 and v2 behind one Service on port `8000`.
* `shuttle`: a client pod with `curl`. Send your test requests from here.

Istio 1.30.5 is installed and access logs are switched on. There is no fault yet. Configure the faults so that:

1.  A `VirtualService` named `navcom` delays **every** request to `navcom` by **2 seconds** with `fault.delay`, and routes it to subset `v1`. It has no abort.
2.  A `VirtualService` named `probe` fails **every** request to `probe` with **503** with `fault.abort`. It has no delay.
3.  A request from `shuttle` to `http://scout:9080/reviews/0` with the header `end-user: jason` still gets a **200**, about 2 seconds late, and the access log of `scout-v2` marks its request to `navcom` with the response flag **`DI`** (delay injected).
4.  A request from `shuttle` to `http://probe:8000/get` gets a **503** at once, the access log of `shuttle` marks it with the response flag **`FI`** (fault injected), and `probe` never receives it.
5.  The `scout` `VirtualService`, the Deployments and the Services stay unchanged.

The grader sends real requests from `shuttle`, reads the access logs of `shuttle`, `scout-v2` and `probe`, and checks both `VirtualService` objects.
