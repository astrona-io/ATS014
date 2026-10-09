# Question

Solve this question on: `terminal`

Astronaut, your mission: stop a forgotten drill from hitting every crew, without throwing the drill away.

The planet `starfleet` runs the Starfleet and the `shuttle` test client:

* `scout` — three ship classes, v1, v2 and v3, on port 9080. The flight plan sends **every** signal to v2, which asks `navcom` for a star rating.
* `navcom` — the navigation computer, on port 9080. Its docking instructions define subset `v1`.
* `shuttle` — your test client, with `curl`.

Somebody added an abort drill to navcom's flight plan that fails **every** signal with `500`. Now every answer from `http://scout:9080/reviews/0` says `"Ratings service is currently unavailable"` instead of showing star ratings.

The test crew still wants the drill, but only for their own signals. Fix navcom's flight plan so that:

1.  The `VirtualService` named `navcom` has **exactly two** rules.
2.  The first rule matches the header `end-user` with the exact value **`tester`**, keeps the drill (abort with `500` for every matching signal), and routes to subset `v1`.
3.  The second rule has no `match` and no `fault`, and routes to subset `v1`.
4.  A signal from the `shuttle` to `http://scout:9080/reviews/0` without a label gets star ratings again.
5.  The same signal with `end-user: tester` still gets `"Ratings service is currently unavailable"`, and a signal with `end-user: tester` straight to `http://navcom:9080/ratings/0` gets a `500` that the shuttle's flight log marks with the flag **`FI`**.
6.  Leave the `scout` flight plan, the Deployments and the Services unchanged.

The grader sends real signals from the `shuttle`, reads its flight log, and checks navcom's flight plan.
