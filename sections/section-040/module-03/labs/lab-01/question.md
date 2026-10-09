# Question

Solve this question on: `terminal`

One pod behind the `httpbin` Service fails every request, yet Kubernetes reports it as ready. Make the client's sidecar proxy stop using it, without removing it from Kubernetes.

The namespace `outlier-demo` holds:

* `httpbin-good`: 1 replica of an HTTP echo server that answers normally.
* `httpbin-bad`: 1 replica of nginx that answers **every request with `503`**. It has no readiness probe that fails, so Kubernetes treats it as ready.
* `httpbin`: one Service on port `8000` in front of **both** pods.
* `tester`: a client pod with `curl`. Send test requests from here.

Istio is installed, every pod in `outlier-demo` has a sidecar proxy, and there is no `DestinationRule`. About half of all requests to `http://httpbin:8000/get` fail.

Do the following:

1. Create a `DestinationRule` named `httpbin` for the host `httpbin` in `outlier-demo`.
2. In its `trafficPolicy.outlierDetection`, set:
   * `consecutive5xxErrors` to **3**
   * `interval` to **`5s`**
   * `baseEjectionTime` to **`30s`**
   * `maxEjectionPercent` to a value that lets an ejection **really happen on a Service with two endpoints**. Think about what the default value does here before you pick a number.
3. Do **not** create any `VirtualService` in `outlier-demo`. Do not scale or delete `httpbin-bad`, and do not change the Service selector. The `tester` proxy must remove the bad endpoint on its own; you must not remove it.

**What the grader checks**

4. `httpbin-good`, `httpbin-bad` and `tester` each have a ready replica, the `httpbin` Service lists exactly two endpoint addresses, and `outlier-demo` has no `VirtualService`.
5. The `DestinationRule` `httpbin` has `consecutive5xxErrors: 3`, `interval: 5s`, `baseEjectionTime: 30s`, and `maxEjectionPercent` of at least **50**.
6. The `tester` proxy's cluster configuration for `httpbin` contains the outlier detection settings.
7. After the grader sends requests from `tester` (up to 240 of them), one endpoint in the `tester` proxy carries the outlier detection failure flag, and `istioctl proxy-config endpoints` shows it with `OUTLIER CHECK: FAILED`.
8. The `httpbin` Service still lists **both** addresses, and `httpbin-bad` is still ready. The ejection lives only in the proxy, not in the Kubernetes objects.
9. At least 32 of 40 new requests from `tester` return `200`.
