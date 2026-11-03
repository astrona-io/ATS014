# Summary

Istio picks the protocol of a Service from the port: the `appProtocol` field first, then the port name. A port named `tcp` makes the sidecar proxy treat the traffic as plain TCP. The proxy then reads no requests, and the `tcp` section of a `VirtualService` applies. A second Service for the same pods, with a port named `tcp`, lets the same application be routed as TCP while the original Service keeps its HTTP behaviour.

A `tcp` route is a list read top to bottom. Its `match` can use `port`, which is the Service port, and its `route` lists destinations with a `weight` next to each one. A `DestinationRule` for the TCP host defines the subsets. The weights should add up to 100. The sidecar proxy of the client holds the route as `weightedClusters` in the listener for the port, and `istioctl proxy-config` shows it.

The weight applies once per connection. The proxy of the client makes one random pick when a connection opens, and every byte of that connection goes to the pod it chose. One `curl` process that sends many requests over one connection reaches one pod. A TCP split is measured with a new connection for every sample, and at least 100 connections are needed to judge an 80/20 split, because the count varies from run to run. An HTTP Service on the same pods splits per request instead.

A rollout is a series of weight changes: 100/0, 90/10, 50/50, 0/100, and back with the same patch. A weight of 0 sends no new connection. A change affects only new connections, so connections that were open before the change stay on their pod until they close. A JSON patch on the two weight paths changes only the weights, while a merge patch replaces the whole `tcp` list.

A `tcp` route on a port that is named `http` never applies, and no error is shown. The signs are a host for the Service in the route table, no weighted clusters in the listener, and answers that ignore the weights. The `VirtualService` and the Service are both valid, so `istioctl analyze` may stay silent. A subset whose labels match no pod causes a second silent fault: connections picked for that subset have no endpoint.

Key facts to remember:

- Port name `tcp` (or `tcp-...`) selects the `tcp` section; port name `http` selects the `http` section.
- `match.port` is the Service port, not the container port.
- Weights apply per connection, so count fresh connections.
- A weight change reaches new connections only.

<!-- astrona:playground:destroy -->
