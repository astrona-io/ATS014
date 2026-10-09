---
estimated_duration: 20m
---

# Question

Solve this question on: `terminal`

The `probe` in the `starfleet` namespace needs protection. One of its pods answers every request with `503`, yet Kubernetes lists it as ready. And nothing stops a client from opening as many requests to the `probe` as it likes.

The namespace `starfleet` holds:

* `probe-v1` and `probe-v2`: two healthy pods of an HTTP echo server behind one `probe` Service on port `8000`. Their `/get` path answers `200`.
* `probe-broken`: a third pod with the same `app: probe` label. It answers **every** request with `503`, and it is `2/2 Running`.
* `shuttle`: a client pod with `curl`. Send single requests from here.
* `fortio`: a load generator that sends many requests at the same time.

Istio 1.30.5 is installed, and every pod in `starfleet` has a sidecar proxy. There is **no `DestinationRule`** for the `probe` yet.

Configure a circuit breaker so that:

1. There is **exactly one** `DestinationRule` for the `probe` host in `starfleet`, and it holds both a `connectionPool` and an `outlierDetection`.
2. The connection pool allows at most **1** TCP connection (`maxConnections: 1`) and at most **1** waiting HTTP request (`http1MaxPendingRequests: 1`).
3. Outlier detection marks an endpoint as failing after **3** 5xx responses in a row (`consecutive5xxErrors`), checks every **5s** (`interval`), and ejects for a base time of **30s** (`baseEjectionTime`).
4. With these three pods, an ejection really happens: the `shuttle` proxy ejects the broken pod.
5. When `fortio` sends 40 requests over 4 parallel connections, its proxy refuses some of them as overflow (`upstream_rq_pending_overflow` above 0).
6. While the broken pod is ejected, at most 1 of 10 single requests from the `shuttle` fails.
7. The five Deployments, their labels and the `probe` Service stay unchanged. Do not add or remove workloads. The `shuttle` proxy must remove the broken pod on its own, so Kubernetes must still list it as an endpoint of the `probe` Service.

The grader sends live requests from `fortio` and the `shuttle` and reads both proxies, so the configuration has to work, not only exist.
