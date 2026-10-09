# Question

Solve this question on: `terminal`

Keep every user of the `httpbin` application on the same stable pod, while a canary version receives a copy of every request.

Namespace `sessions` runs two versions of `httpbin` behind one Service:

* `httpbin-stable`: **3 replicas**, pods labelled `version: stable`. Holds per-user state in memory.
* `httpbin-canary`: **2 replicas**, pods labelled `version: canary`. Holds no state.
* `httpbin`: one Service on port 8000 selecting on `app` only
* `tester`: a client pod with `curl`

Istio is installed, every pod has its sidecar proxy (the Envoy proxy that Istio adds to each pod), and there is no `DestinationRule` and no `VirtualService`.

The canary is not ready for users, but it needs realistic load. Deliver a configuration where every user keeps reaching the same stable pod, while the canary receives a copy of everything. **Mirroring** does this: the `mirror` field of a `VirtualService` rule makes the caller's sidecar proxy send a copy of each request to a second destination and ignore the copy's response.

**Destination policy**

1.  A `DestinationRule` named `httpbin` for host `httpbin`, defining exactly two subsets: **`stable`** (`version: stable`) and **`canary`** (`version: canary`).
2.  A **host-level** `trafficPolicy` using **`consistentHash`** on the header **`x-session`**.
3.  A **subset-level** `trafficPolicy` on the **`canary`** subset only, using **`simple: LEAST_REQUEST`**. The canary is being load tested, so it must spread rather than pin.
4.  The `stable` subset must carry **no** `trafficPolicy` of its own. It inherits the host-level one.

**Routing**

5.  A `VirtualService` named `httpbin` for host `httpbin` with exactly **one** `http` rule.
6.  That rule routes **100% of caller traffic to subset `stable`**.
7.  The same rule **mirrors** its requests to subset **`canary`**, with `mirrorPercentage` set explicitly to **100**.

**What the grader checks**

8.  Twelve requests carrying the same `x-session` value all reach **one single stable endpoint**.
9.  Twelve requests with **no** `x-session` header reach more than one endpoint, because a request with nothing to hash gets normal load balancing.
10. No caller response comes from a canary pod: the canary must be a mirror target, not a route destination.
11. The canary receives a copy of nearly every request: for 40 requests sent, the canary pods' proxy access logs show at least 30 new `GET /get` lines. No caller traffic is routed to the canary, so every request it logs is a mirrored copy.
12. The `stable` and `canary` clusters report **different** `lbPolicy` values in the `tester` pod's proxy configuration (`istioctl proxy-config cluster`), and the `tester` pod's routes hold a mirror policy.
13. Replica counts are unchanged (3 and 2), and the Service selector still selects on `app` only.
