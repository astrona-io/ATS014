# Summary

A request needs a TCP connection, and the sidecar proxy of the caller controls how that connection is opened, kept and closed. All of these settings live in the `connectionPool` block of the `DestinationRule`, and `istiod` sends them to the proxy as part of the cluster configuration. You can read every one of them with `istioctl proxy-config cluster -o json`.

The connect timeout, `connectionPool.tcp.connectTimeout`, limits only the time the proxy waits for a new connection to open. The default is 10 seconds. When it expires, the client gets a `503` with the response flag `UF`. This is different from the route `timeout` of a `VirtualService`, which limits the whole request and gives a `504` with the flag `UT`.

Three more settings control a connection that is already open. `connectionPool.http.idleTimeout` closes a connection after a period without active requests, and its default is one hour. `connectionPool.tcp.maxConnectionDuration` closes a connection a fixed time after it was established, whether it is busy or idle. `connectionPool.tcp.tcpKeepalive` makes the operating system send probes on an idle connection: `time` before the first probe, `interval` between probes, and `probes` as the number that may go unanswered. The proxy shows the maximum duration and idle timeout as duration strings and the keepalive values as numbers.

The Kubernetes `Service` field `spec.trafficDistribution: PreferClose` asks every client to prefer endpoints in its own zone. You prove it by counting which pods answer: requests from a client in `zone-a` stay in `zone-a` while an endpoint there is available. It is a preference, not a guarantee, and it has no weights. It does not notice an endpoint that stays ready and returns errors. Failover away from such an endpoint still needs `outlierDetection` in the `DestinationRule` of the host, with a `maxEjectionPercent` that can eject.

Key facts to remember:

- `connectTimeout` fails with `503` and `UF`; the route `timeout` fails with `504` and `UT`.
- `idleTimeout` is under `http`; `connectTimeout`, `maxConnectionDuration` and `tcpKeepalive` are under `tcp`.
- The cluster JSON shows `10m` as `600s`, and the keepalive durations as whole seconds.
- `trafficDistribution` belongs to the `Service`, not to a `DestinationRule`.

<!-- astrona:playground:destroy -->
