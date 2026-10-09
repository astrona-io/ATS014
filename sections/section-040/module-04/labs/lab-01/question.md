# Question

Solve this question on: `terminal`

The service in your own zone has started to fail, and your requests must move to the healthy zone without anyone removing the broken pod.

Namespace `locality-demo` has one Service with two endpoints in two declared localities. A locality is the region and zone a pod runs in:

* `httpbin-zone-a`: locality **`local/zone-a`**, 1 replica. It **returns 503 to every request** while it still passes its readiness probe.
* `httpbin-zone-b`: locality **`local/zone-b`**, 1 replica. Healthy.
* `httpbin`: one Service on port 8000 in front of both.
* `tester`: a client pod with `curl`, running on a node labelled `local/zone-a`, so **`zone-a` is the client's own locality**.

Istio is installed, every pod has a sidecar proxy, and there is no `DestinationRule`.

With no `DestinationRule`, the requests go to both endpoints, so about half of them reach the broken `zone-a` pod and fail. Move the traffic away from that locality.

1.  Create a `DestinationRule` named `httpbin` for host `httpbin`.
2.  Configure **`outlierDetection`** so that the proxy can mark the failing endpoint unhealthy:
    *   `consecutive5xxErrors` **2**
    *   `interval` **`5s`**
    *   `baseEjectionTime` **`30s`**
    *   `maxEjectionPercent` at a value that can really eject one of two endpoints
3.  Configure **`loadBalancer.localityLbSetting`** with `enabled: true`.
4.  Do **not** scale, delete or fix `httpbin-zone-a`, and do not change the Service selector. The traffic must leave the locality because the proxy judged the endpoint unhealthy, not because you removed it.

**What the grader checks**

5.  Both endpoints still exist, and both Deployments still run 1 replica.
6.  The `DestinationRule` contains both `outlierDetection` and `localityLbSetting`. A locality setting **without** outlier detection is the mistake this task is about: nothing ever marks an endpoint unhealthy, so nothing ever fails over.
7.  `maxEjectionPercent` is high enough to eject one of two endpoints.
8.  Both endpoints show a non-empty locality in the proxy's endpoint list.
9.  After the grader sends traffic, the `zone-a` endpoint shows `OUTLIER CHECK: FAILED`, or the ejection counters have increased.
10. Almost all requests measured afterwards succeed, because they now go to `zone-b`.
