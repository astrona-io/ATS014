# Question

Solve this question on: `terminal`

Astronaut, your mission: one probe ship is doing all the work while three others sit idle. Spread the signals across the whole squadron again.

The planet `starfleet` runs:

* `probe-v1` (3 pods) and `probe-v2` (1 pod), all labelled `app: probe`, behind one Service `probe` on port `8000`. The path `/hostname` answers with the name of the pod that served the signal.
* `shuttle`, a client pod with `curl`.

Istio is installed and every pod has its sidecar. A `DestinationRule` named `probe` already exists. Every signal the shuttle sends to `probe` lands on the same pod.

Change the probe's docking instructions so that:

1.  The `DestinationRule` named `probe` in `starfleet` (host `probe`) uses **`simple: ROUND_ROBIN`** as its host-level `trafficPolicy.loadBalancer`.
2.  The `DestinationRule` contains **no `consistentHash`** anywhere.
3.  The shuttle's proxy holds a round robin cluster for `probe` (check it with `istioctl proxy-config cluster`).
4.  16 signals from the shuttle to `http://probe:8000/hostname` reach **all four** probe pods, and no pod answers more than 8 of them.
5.  Leave the ships alone: `probe-v1` keeps 3 replicas, `probe-v2` keeps 1, no Deployment is added or removed, and the `probe` Service keeps selecting `app: probe`.

The grader reads the `DestinationRule`, reads the shuttle's proxy, and sends live signals, so the spread has to really happen.
