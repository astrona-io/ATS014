# Question

Solve this question on: `terminal`

Namespace `outlier-demo` has one Service with two endpoints, one of which is poison:

* `httpbin-good` — 1 replica, answers normally
* `httpbin-bad` — 1 replica of nginx that returns **503 to every request**, while passing its readiness probe. Kubernetes considers it perfectly healthy.
* `httpbin` — one Service on port 8000 in front of **both**
* `tester` — a client pod with `curl`

Istio is installed, every pod is injected, and there is no `DestinationRule`. Roughly half of all traffic currently fails.

Make the client proxy notice the bad endpoint and stop using it.

1.  Create a `DestinationRule` named `httpbin` for host `httpbin`.
2.  In its `trafficPolicy.outlierDetection`, set:
    *   `consecutive5xxErrors` to **3**
    *   `interval` to **`5s`**
    *   `baseEjectionTime` to **`30s`**
    *   `maxEjectionPercent` to a value that lets an ejection **actually happen on a two-endpoint service**. Think about what the default does here before you pick a number.
3.  Do **not** add a `VirtualService`, do not scale or delete `httpbin-bad`, and do not change the Service selector. The bad endpoint must be removed by the proxy's own judgement, not by you removing it.

**What the grader checks**

4.  The four fields are present with the required values, and `maxEjectionPercent` is high enough to eject one of two endpoints.
5.  The policy is live in the `tester` proxy's cluster configuration.
6.  After driving traffic, `outlier_detection.ejections_active` for the `httpbin` cluster is at least 1, **or** `ejections_total` has increased — an ejection really happened.
7.  `istioctl proxy-config endpoints` shows one endpoint with `OUTLIER CHECK: FAILED`.
8.  `kubectl get endpoints httpbin` still lists **both** addresses, and `httpbin-bad` is still running. The ejection is the proxy's opinion, not a change to the Kubernetes object.
9.  Traffic measured after the ejection is substantially healthier than the 50% failure rate you started with.
