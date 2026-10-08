# Question

Solve this question on: `terminal`

Astronaut, this is your section 030 mission: keep every user docked to the same stable ship, while a test ship quietly receives a copy of every signal.

Namespace `sessions` runs two versions of `httpbin` behind one Service:

* `httpbin-stable` — **3 replicas**, pods labelled `version: stable`. Holds per-user state in memory.
* `httpbin-canary` — **2 replicas**, pods labelled `version: canary`. Holds no state.
* `httpbin` — one Service on port 8000 selecting on `app` only
* `tester` — a client pod with `curl`

Istio is installed, every pod is injected, and there is no `DestinationRule` and no `VirtualService`.

The canary is not ready for users, but it needs realistic load. Deliver a configuration where every user keeps reaching the same stable pod, while the canary quietly receives a copy of everything.

**Destination policy**

1.  A `DestinationRule` named `httpbin` for host `httpbin`, defining exactly two subsets: **`stable`** (`version: stable`) and **`canary`** (`version: canary`).
2.  A **host-level** `trafficPolicy` using **`consistentHash`** on the header **`x-session`**.
3.  A **subset-level** `trafficPolicy` on the **`canary`** subset only, using **`simple: LEAST_REQUEST`**. The canary is being load tested, so it must spread rather than pin.
4.  The `stable` subset must carry **no** `trafficPolicy` of its own — it inherits the host-level one.

**Routing**

5.  A `VirtualService` named `httpbin` for host `httpbin` with exactly **one** `http` rule.
6.  That rule routes **100% of caller traffic to subset `stable`**.
7.  The same rule **mirrors** its requests to subset **`canary`**, with `mirrorPercentage` set explicitly to **100**.

**What the grader checks**

8.  Twelve requests carrying the same `x-session` value all reach **one single stable endpoint**.
9.  Twelve requests with **no** `x-session` header reach more than one endpoint — nothing to hash means normal load balancing.
10. No caller response comes from a canary pod: the canary must be a mirror target, not a route destination.
11. The canary receives a copy of essentially every request, identifiable by the rewritten `-shadow` authority in its proxy access log.
12. The `stable` and `canary` clusters report **different** `lbPolicy` values in the proxy dump.
13. Replica counts are unchanged (3 and 2), and the Service selector still selects on `app` only.
