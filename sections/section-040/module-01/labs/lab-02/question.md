# Question

Solve this question on: `terminal`

The `jason` requests to `scout` wait more than 3 seconds for a slow `navcom`, and a timeout that was meant to stop this never fires. Move the timeout to the route where it really fires.

The `starfleet` namespace runs the Starfleet sample app and the `shuttle` test client:

* `scout` — a backend in three versions, v1, v2 and v3, on port 9080. A `VirtualService` sends requests with the header `end-user: jason` to subset v2 and everything else to subset v1. Only v2 and v3 call `navcom`.
* `navcom` — a backend on port 9080. A delay fault makes every request to it wait **3 seconds**. A delay fault is a `VirtualService` setting that makes the sidecar proxy hold each request before it forwards it.
* `shuttle` — the test client, with `curl`.

Someone tried to protect the `jason` requests from the slow `navcom` by adding `timeout: 1s` to the `navcom` `VirtualService`, on the same rule as the delay fault. It does nothing: the `jason` requests still take more than 3 seconds.

Fix it so that:

1.  The `navcom` `VirtualService` keeps the delay fault exactly as it is: `fixedDelay: 3s` for 100 percent of requests, routed to subset `v1`.
2.  The `navcom` `VirtualService` has **no** `timeout` on any rule.
3.  The `scout` `VirtualService` still sends `end-user: jason` to subset `v2` in its first rule, and everything else to subset `v1` in its last rule.
4.  The `jason` rule in the `scout` `VirtualService` has a `timeout` of **at most 1 second**.
5.  A request from `shuttle` to `http://scout:9080/reviews/0` with `end-user: jason` gets a **504** after about one second, and the `shuttle` sidecar proxy's access log shows it with the response flag **`UT`**.
6.  A request without the `end-user: jason` header still gets a **200** in well under a second.
7.  Leave the Deployments and Services unchanged.

The grader sends real requests from `shuttle`, reads its access log, and checks both `VirtualService` objects.
