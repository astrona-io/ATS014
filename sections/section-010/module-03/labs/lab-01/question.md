---
estimated_duration: 15m
---

# Question

Solve this question on: `terminal`

The old `v1` version of the `scout` backend is being retired, and the Starfleet must keep working while you do it.

The namespace `starfleet` holds these workloads:

* `scout-v1`, `scout-v2` and `scout-v3`: three versions behind one `scout` Service on port `9080`. Each pod carries the labels `app: scout` and `version: v1`, `v2` or `v3`.
* `shuttle`: a client pod with `curl`. Send your test requests from here.
* `patrol`: a client pod that sends one request to `http://scout:9080/reviews/0` every half second, for the whole lab. Its sidecar proxy writes every request to its access log.
* `bridge`, `cargo` and `navcom`: the other workloads of the sample app.

Istio 1.30.5 is installed, and every pod in `starfleet` has its sidecar proxy, the Envoy container that Istio adds to each pod. Two Istio objects already exist, both named `scout`:

* A `DestinationRule` with the subsets `v1`, `v2` and `v3`. A subset is a named group of pods; each of these selects pods by their `version` label.
* A `VirtualService` that sends every request to the subset `v1`. A `VirtualService` holds the routing rules for a host.

Retire `v1` so that:

1.  The `VirtualService` named `scout` in `starfleet` has **exactly two rules**, in this order: requests with the header `end-user: jason` go to the subset **`v3`**, and every other request goes to the subset **`v2`**. Each rule has one destination.
2.  The `DestinationRule` named `scout` defines **exactly two subsets**: `v2` and `v3`, each selecting `version` equal to its own name.
3.  No route points at a subset or host that does not exist (`istioctl analyze -n starfleet` reports no `IST0101`).
4.  All 10 out of 10 requests sent with the header `end-user: jason` are answered by `scout-v3`, and all 10 out of 10 requests without it by `scout-v2`.
5.  **The `patrol` pod never sees a failed request.** Its proxy's access log must not contain a single `5xx` response for `/reviews/0`, and it must hold at least 20 requests.
6.  Keep exactly one `VirtualService` for `scout`. Leave the Deployments, their pod labels and the Services unchanged, and do not stop or remove `patrol`.

Each `scout` response contains the name of the pod that sent it (`"podname": "scout-v2-..."`), so you can see which version answered.

If `patrol` logged failures while you were trying things, you can give it a clean access log by restarting it: `kubectl rollout restart deploy/patrol -n starfleet`. Wait at least 30 seconds before you submit, so it has sent enough requests to be judged.

The grader sends live requests from the `shuttle` pod, runs `istioctl analyze`, and reads the access log of the `patrol` proxy. So the change has to be safe, not only finished.
