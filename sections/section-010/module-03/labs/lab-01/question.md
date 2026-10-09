---
estimated_duration: 15m
---

# Question

Solve this question on: `terminal`

Astronaut, the old scout ship class `v1` is being retired, and the fleet must keep flying while you do it.

The planet `starfleet` holds the Starfleet:

* `scout-v1`, `scout-v2` and `scout-v3`: three ship classes behind one `scout` Service on port `9080`. Each pod carries the labels `app: scout` and `version: v1`, `v2` or `v3`.
* `shuttle`: a client pod with `curl`. Send your test signals from here.
* `patrol`: a ship that sends one signal to `http://scout:9080/reviews/0` every half second, for the whole mission. Its sidecar writes every signal to its flight log.
* `bridge`, `cargo` and `navcom`: the rest of the fleet.

Istio 1.30.5 is installed, and every pod in `starfleet` has its sidecar. Two Istio objects already exist, both named `scout`:

* A `DestinationRule` (the docking instructions) with the subsets `v1`, `v2` and `v3`, each selecting on the pods' `version` label.
* A `VirtualService` (the flight plan) that sends every signal to the subset `v1`.

Retire `v1` so that:

1.  The `VirtualService` named `scout` in `starfleet` has **exactly two rules**, in this order: signals with the header `end-user: jason` go to the subset **`v3`**, and every other signal goes to the subset **`v2`**.
2.  The `DestinationRule` named `scout` defines **exactly two subsets**: `v2` and `v3`, each selecting `version` equal to its own name.
3.  No route points at a subset or host that does not exist (`istioctl analyze -n starfleet` reports no `IST0101`).
4.  All 10 out of 10 signals sent with the header `end-user: jason` are answered by `scout-v3`, and all 10 out of 10 signals without it by `scout-v2`.
5.  **The patrol never sees a failed signal.** Its flight log must not contain a single `5xx` answer for `/reviews/0`.
6.  Keep exactly one `VirtualService` for `scout`. Leave the Deployments, their pod labels and the Services unchanged, and do not stop or remove the patrol.

Each `scout` answer contains the name of the pod that sent it (`"podname": "scout-v2-..."`), so you can see which ship class answered.

If the patrol logged failures while you were trying things, you can give it a clean flight log by restarting it: `kubectl rollout restart deploy/patrol -n starfleet`. Wait at least 30 seconds before you submit, so it has flown long enough to be judged.

The grader sends live signals from the `shuttle` pod, runs `istioctl analyze`, and reads the patrol's flight log, so the change has to be safe, not merely finished.
