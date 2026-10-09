# Question

Solve this question on: `terminal`

One version of the `httpbin` application must keep each user on the same pod, while a second version spreads its requests evenly.

Namespace `lb-demo` runs two versions of `httpbin` behind one Service:

* `httpbin-stable`: **3 replicas**, pods labelled `version: stable`
* `httpbin-canary`: **2 replicas**, pods labelled `version: canary`
* `httpbin`: one Service on port 8000 selecting on `app` only
* `tester`: a client pod with `curl`

Istio is installed, every pod has its sidecar proxy (the Envoy proxy that Istio adds to each pod), and there is no `DestinationRule` and no `VirtualService`.

The stable version holds per-user state in memory, so its users must keep reaching the same pod. The canary holds no state, and its requests should simply be spread evenly while it is being load tested.

Configure host `httpbin` in namespace `lb-demo` with:

1.  A `DestinationRule` named `httpbin` for host `httpbin`, defining exactly two subsets: **`stable`** (`version: stable`) and **`canary`** (`version: canary`).
2.  A **host-level** `trafficPolicy` using **`consistentHash`** on the header **`x-user`**.
3.  A **subset-level** `trafficPolicy` on the **`canary`** subset only, using **`simple: ROUND_ROBIN`**, overriding the host-level policy for that subset.
4.  A `VirtualService` named `httpbin` for host `httpbin` with two `http` rules, in this order:
    *   requests carrying the header **`x-track: canary`** go to subset **`canary`**
    *   everything else goes to subset **`stable`**

**What the grader checks**

5.  Twelve requests carrying the same `x-user` value and no `x-track` header all reach **one single endpoint**, so the session affinity is real.
6.  Twelve requests carrying `x-track: canary` **and** the same `x-user` value reach **more than one endpoint**, because the subset policy overrides the host policy.
7.  Twelve requests with **no** `x-user` header and no `x-track` reach more than one endpoint, because a request with nothing to hash falls back to normal load balancing.
8.  The `tester` pod's proxy configuration (`istioctl proxy-config cluster`) shows **different `lbPolicy` values** for the `stable` and `canary` clusters.
9.  Replica counts are unchanged: `httpbin-stable` still has 3 and `httpbin-canary` still has 2.
10. The `httpbin` Service selector still selects on `app` only.
