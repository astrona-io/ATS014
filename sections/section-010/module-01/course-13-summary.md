# Summary

A Kubernetes Service selects its pods by one label, such as `app=scout`, and cannot read a request. So without Istio rules, requests to `scout` land on a random mix of v1, v2 and v3. In the mesh, the sidecar proxy of the client pod chooses the destination before the request leaves. The server's proxy only accepts it. So when the wrong version answers, you debug the client's proxy.

Two Istio objects control that choice. A `DestinationRule` names groups of pods. Each subset selects pods by pod labels, such as `version: v1`, and `istiod` turns it into its own Envoy cluster, such as `outbound|9080|v2|scout.starfleet.svc.cluster.local`. A `DestinationRule` alone moves no traffic. A subset that selects no pod is valid configuration, and requests sent to it fail with `503 UH`.

A `VirtualService` decides where requests go. `spec.hosts` is the host the client calls, and `destination.host` is the Service the proxy sends the request to. Its `http` field is an ordered list of rules. Each rule has an optional `match` and a required `route`. A match can read headers, the path, query parameters, the method and the labels of the calling pod. Header names ignore case, but header values do not.

The details of a match decide what it really does. `exact` compares character for character, `prefix` compares the start of the text and ignores `/`, and `regex` uses RE2 and must fit the whole value. Conditions inside one `-` item are combined with AND, and separate `-` items are combined with OR. The route table in the client's proxy shows which one you wrote.

The proxy reads the rules from the top and uses the first rule that matches. The most specific rule goes first, and the catch-all, a rule with no `match`, goes last. A catch-all placed first makes every rule below it unreachable. A missing catch-all gives `404 NR` to every request that matches no rule.

Istio fills in a short host name from the namespace of the object that holds it. A `VirtualService` in the wrong namespace is valid but describes a Service that does not exist, so it never matches. Full names (FQDN) work from any namespace.

A matched rule can do more than choose a destination. `redirect` answers the client with a 3xx and ends the request at the client's proxy. `rewrite` changes the path or `Host` on the way to the server, and after a `prefix` match it replaces only the prefix. `headers` sets, adds or removes request and response headers, per rule or per destination. `corsPolicy` lets the proxy answer browser preflight requests, but it is not a security control.

All of this needs HTTP. Istio decides a port's protocol from `appProtocol`, then from the port name, and only then by protocol sniffing. A port declared as `tcp` removes the Service from the route table, so every `http` rule for it stops working with no error. A `tcp` rule matches only on port and source, a `tls` rule only on the SNI name, and both balance load per connection instead of per request.

Key facts to remember:

- An object that `kubectl` accepted is not yet an object the proxy acts on. Check with `istioctl proxy-status` and `istioctl proxy-config`.
- The order of checks is `kubectl get -A`, `istioctl analyze -A`, the client's access log, `istioctl proxy-status`, then `istioctl proxy-config routes`.
- `NR` comes with `404` and means no route matched; `NC` comes with `503` and means the route names a subset with no cluster (`IST0101`); `UH` comes with `503` and means the cluster has no endpoints (`IST0173`).
- `IST0130` means a rule is never used because a catch-all comes before it.
- Apply a `DestinationRule` before the `VirtualService` that uses it ("make before break").

<!-- astrona:playground:destroy -->
