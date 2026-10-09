---
estimated_duration: 20m
---

# Question

Solve this question on: `terminal`

Astronaut, the probe is in trouble. On the planet `starfleet`, it answers some signals with `503`, and every one of those failures is sent to it again and again. A ship that is already struggling gets six times the work.

The planet `starfleet` holds:

* `probe-v1` and `probe-v2`: the echo probe, two pods behind one `probe` Service on port `8000`. The path `/status/503` always answers `503`, so you can test failures on purpose.
* `shuttle`: a client pod with `curl`. Send your test signals from here.

Istio 1.30.5 is installed, and every pod in `starfleet` has its sidecar. Two Istio objects already exist:

* A `DestinationRule` named `probe` (the shields). It sets `tcp.maxConnections`, `http.http1MaxPendingRequests` and `http.maxRequestsPerConnection` to `1`. **The shields are correct.**
* A `VirtualService` named `probe` (the flight plan). It routes every signal to the probe, with a retry policy that is too aggressive.

Change the retry policy so that:

1.  The `VirtualService` named `probe` in `starfleet` still routes every signal to the `probe` Service and **still has a retry policy**.
2.  `retries.attempts` is **1 or 2**.
3.  `retries.retryOn` includes **`connect-failure`**, so signals that never reached the probe still get another try.
4.  `retries.retryOn` does **not** retry the probe's own `5xx` answers: it contains none of `5xx`, `gateway-error`, `retriable-status-codes` or `503`.
5.  When the `shuttle` sends 5 signals to `http://probe:8000/status/503`, all 5 are answered with `503`, and the probe receives **exactly 5** signals, not one more.
6.  There is exactly one `VirtualService` for the probe.
7.  The `DestinationRule` named `probe` is **left unchanged**. Leave the Deployments and the Service unchanged, and do not add or remove workloads.

The grader counts the signals that arrive at the probe pods in their flight logs, so the fix has to work, not merely exist.
