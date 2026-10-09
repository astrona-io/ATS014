---
estimated_duration: 20m
---

# Question

Solve this question on: `terminal`

Astronaut, the probe on the planet `starfleet` needs shields. One of its ships answers every signal with `503`, yet Kubernetes lists it as healthy. And nothing stops a sender from opening as many signals to the probe as it likes.

The planet `starfleet` holds:

* `probe-v1` and `probe-v2`: two healthy ships behind one `probe` Service on port `8000`. Their `/get` path answers `200`.
* `probe-broken`: a third ship with the same `app: probe` label. It answers **every** signal with `503`, and it is `2/2 Running`.
* `shuttle`: a client pod with `curl`. Send single signals from here.
* `fortio`: a load generator that sends many signals at the same time.

Istio 1.30.5 is installed, and every pod in `starfleet` has its sidecar. There is **no `DestinationRule`** for the probe yet.

Raise both shields so that:

1.  There is **exactly one** `DestinationRule` for the `probe` host in `starfleet`, and it holds both a `connectionPool` and an `outlierDetection`.
2.  The connection pool allows at most **1** TCP connection (`maxConnections: 1`) and at most **1** waiting HTTP signal (`http1MaxPendingRequests: 1`).
3.  Outlier detection marks a ship as failing after **3** 5xx answers in a row, checks every **5s**, and ejects for a base time of **30s**.
4.  On these three ships, an ejection really happens: the broken ship is ejected.
5.  When `fortio` sends 40 signals over 4 parallel connections, its proxy refuses some of them as overflow.
6.  While the broken ship is ejected, at most 1 of 10 single signals from the `shuttle` fails.
7.  Leave the Deployments, their labels and the `probe` Service unchanged. Do not add or remove workloads. The broken ship must be removed by the proxy's own judgement, so Kubernetes must still list it.

The grader sends live signals from `fortio` and the `shuttle`, and reads both proxies, so the shields have to work, not merely exist.
