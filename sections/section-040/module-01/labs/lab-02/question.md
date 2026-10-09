# Question

Solve this question on: `terminal`

Astronaut, your mission: give jason's signals an abort window that really fires.

The planet `starfleet` runs the Starfleet and the `shuttle` test client:

* `scout` — three ship classes, v1, v2 and v3, on port 9080. The flight plan sends signals with the header `end-user: jason` to v2 and everything else to v1. Only v2 and v3 call `navcom`.
* `navcom` — the navigation computer, on port 9080. A delay drill makes every signal to it wait **3 seconds**.
* `shuttle` — your test client, with `curl`.

Someone tried to protect jason from the slow navigation computer by adding `timeout: 1s` to navcom's flight plan, on the same rule as the delay drill. It does nothing: jason's signals still take more than 3 seconds.

Fix it so that:

1.  navcom's flight plan keeps the delay drill exactly as it is: `fixedDelay: 3s` for 100 percent of signals, routed to subset `v1`.
2.  navcom's flight plan has **no** `timeout` on any rule.
3.  The `scout` flight plan still sends `end-user: jason` to subset `v2` in its first rule, and everything else to subset `v1` in its last rule.
4.  jason's rule in the `scout` flight plan has a `timeout` of **at most 1 second**.
5.  A signal from the `shuttle` to `http://scout:9080/reviews/0` with `end-user: jason` gets a **504** after about one second, and the shuttle's flight log shows it with the flag **`UT`**.
6.  A signal without jason's label still gets a **200** in well under a second.
7.  Leave the Deployments and Services unchanged.

The grader sends real signals from the `shuttle`, reads its flight log, and checks both flight plans.
