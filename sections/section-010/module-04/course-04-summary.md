# Summary

A `VirtualService` that owns a host can hand part of its route table to other `VirtualService` objects. The root has the `hosts` and the rule with `delegate`, which names another object by `name` and `namespace`. The delegate has no `hosts` and no `gateways`, and it holds `http` rules only. `istiod` merges the root and its delegates into one route table before it sends the table to the proxies. The root's `match` narrows the delegate's `match`, so a request must satisfy both. Delegation goes one level deep, and a rule with `delegate` has no `route` of its own.

The `exportTo` field controls which namespaces receive a `VirtualService` or a `DestinationRule`. The value `"."` is the object's own namespace, `"*"` is every namespace and is the default, `"~"` is no namespace, and a namespace name is that namespace. A client in a namespace that does not receive an object behaves as if the object did not exist. A route to a subset needs the `DestinationRule` too: if the `VirtualService` reaches a namespace and the `DestinationRule` does not, requests from there fail with `503` and the response flag `NC`. `exportTo` limits configuration, not traffic, so it is not access control.

The `match` of an `http` rule can also depend on the sender and the destination port. `sourceLabels` compares the labels of the sending pod, `sourceNamespace` compares its namespace, and `port` compares the Service port that the request uses. `istiod` puts such a rule only into the route tables of the proxies that fit. These matches need a sidecar proxy on the sender, they need `mesh` in `gateways` when `gateways` is set, and they are not proof of identity.

Key facts to remember:

- A delegate `VirtualService` has no `hosts`, no `gateways` and no `tcp` or `tls` routes.
- A rule has `delegate` or `route`, not both.
- The default for `exportTo` is all namespaces; `"."` limits an object to its own namespace.
- Export a `DestinationRule` to every namespace that uses its subsets.
- A client in another namespace uses the full host name, for example `probe.starfleet.svc.cluster.local`.
- `sourceLabels` and `sourceNamespace` route requests; they do not authenticate or deny them.

<!-- astrona:playground:destroy -->
