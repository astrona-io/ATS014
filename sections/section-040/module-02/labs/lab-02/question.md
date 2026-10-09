---
estimated_duration: 20m
---

# Question

Solve this question on: `terminal`

The `probe` in the `starfleet` namespace is struggling. It answers some requests with `503`, and the client proxies send every one of those failures to it again and again. A service that is already failing gets six times the work.

The namespace `starfleet` holds:

* `probe-v1` and `probe-v2`: an HTTP echo server, two pods behind one `probe` Service on port `8000`. The path `/status/503` always answers `503`, so you can test failures on purpose.
* `shuttle`: a client pod with `curl`. Send your test requests from here.

Istio 1.30.5 is installed, and every pod in `starfleet` has a sidecar proxy. Two Istio objects already exist:

* A `DestinationRule` named `probe`. It sets the connection pool limits `tcp.maxConnections`, `http.http1MaxPendingRequests` and `http.maxRequestsPerConnection` to `1`. **These limits are correct.**
* A `VirtualService` named `probe`. It routes every request to the `probe` Service, with a retry policy that is too aggressive.

Change the retry policy so that:

1.  The `VirtualService` named `probe` in `starfleet` still routes every request to the `probe` Service and **still has a retry policy**.
2.  `retries.attempts` is **1 or 2**.
3.  `retries.retryOn` includes **`connect-failure`**, so requests that never reached the probe still get another try.
4.  `retries.retryOn` does **not** retry the probe's own `5xx` answers: it contains none of `5xx`, `gateway-error`, `retriable-status-codes` or `503`.
5.  When the `shuttle` sends 5 requests to `http://probe:8000/status/503`, all 5 are answered with `503`, and the probe pods receive **exactly 5** requests, not one more.
6.  There is exactly one `VirtualService` for the probe.
7.  The `DestinationRule` named `probe` is **left unchanged**. Leave the Deployments and the Service unchanged, and do not add or remove workloads: `starfleet` must keep exactly its 3 Deployments.

The grader counts the requests that arrive at the probe pods in their sidecar proxies' access logs, so the fix has to work, not only exist.
