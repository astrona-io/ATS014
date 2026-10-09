# Summary

Fault injection makes the sidecar proxy (Envoy) fake a failure on purpose, so you can see how your services and your resilience settings behave before a real service fails. The applications do not change, and they cannot tell an injected fault from a real one. You write the fault as a `fault` block on an `http` rule of a `VirtualService`.

`fault.delay` holds a request for `fixedDelay` and then sends it on, so the client still gets a correct response, only late. `fault.abort` answers the request at once with the status you choose, and the request never leaves the client's pod. Both can sit on one rule. The proxy decides each one on its own, so a request can be delayed and then aborted.

The fault belongs on the `VirtualService` of the service that should look slow or broken, but the sidecar proxy of the client applies it. That is why the evidence is in the client's access log: `DI` for an injected delay and `FI` with `fault_filter_abort` for an injected abort. The destination gets a delayed request with its own timing untouched, and it never sees an aborted request at all.

A fault without a `match` hits every client of a service. Put the fault on a first rule that only test requests match, and keep a plain rule below it for everyone else. `headers` matches what a request carries, and `sourceLabels` matches the labels of the pod that sends it. A header match only works through a chain of services if the middle application copies the header onto its own request.

Faults exist to test timeouts and retries. A rule with a `fault` ignores its own `timeout` and `retries`, because the fault filter runs before the router that sends, retries and times the request. So the timeout or retry policy must sit on the client's route, one hop away from the fault. A forgotten fault looks like a real outage, and you find it in the access log flags and in the route configuration of the proxy.

Key facts to remember:

- `percentage.value` is a percent: `0.1` is one request in a thousand. Without a `percentage` block, every matching request gets the fault.
- A delay longer than the client's timeout gives a `504` with `UT` in the client's access log, and `DI` one hop further.
- An abort never reaches a pod, so it cannot test outlier detection.
- In the proxy's route configuration, a fault appears under the key `envoy.filters.http.fault`.
- `kubectl get virtualservice -A` and a search for `DI` or `FI` rule out a forgotten fault quickly.

<!-- astrona:playground:destroy -->
