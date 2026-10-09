# Summary

Every request to a Service with several pods goes to exactly one pod, and the sidecar proxy of the sending pod picks it. The proxy makes three decisions in order: it matches a rule of the `VirtualService`, picks a subset, and then picks one endpoint in that subset. Because the endpoint comes last, the number of pods never changes which subset is picked, and stickiness never keeps a user on one version in a weighted split. To keep a user on one version, you route by header instead.

The `simple` form of `trafficPolicy.loadBalancer` names a standard algorithm that spreads requests. `LEAST_REQUEST` is Istio's default; it picks two random pods and uses the less busy one, so its spread looks a little uneven. `ROUND_ROBIN` takes each pod in turn, `RANDOM` picks any pod, and `PASSTHROUGH` switches the choice off and connects to the original address. The cluster dump from `istioctl proxy-config cluster` shows the algorithm as `lbPolicy`. Round robin is Envoy's own default, so it shows no `lbPolicy` line at all.

The `consistentHash` form pins a value to a pod instead. Envoy places every pod at many points on a ring, hashes the value, and moves clockwise to the first pod point. Nothing is stored, so the same value reaches the same pod every time, and the proxy shows the policy as `RING_HASH`. Two values can land on the same pod; that is a collision, not a bug. Stickiness is best effort: when a pod joins or leaves, Envoy rebuilds the ring and some users move. A request that does not carry the hashed value falls back to normal load balancing, with no error.

You can hash a header, a cookie, the source IP address or a query parameter. A cookie with a `ttl` makes the sidecar proxy create the cookie for a first-time visitor; without `ttl`, the proxy only hashes a cookie the client already has. The source IP pins every request from one address to one pod, which is a trap behind a gateway or any shared address.

A `trafficPolicy` can sit at host, subset or port level, and the most specific level wins. A subset inherits every top-level field it does not set, and a field it does set replaces the host's whole field, with nothing merged inside it. A port-level policy names the Service port, not the container port. The cluster dump shows the real policy of each subset and each port, so it is the proof to check after every change.

Key facts:

- `simple` and `consistentHash` cannot be set together in one `loadBalancer`.
- `LEAST_REQUEST` is the Istio default; a missing `lbPolicy` line means `ROUND_ROBIN`.
- `consistentHash` appears as `RING_HASH` in the proxy.
- `httpCookie` needs a `ttl` for the proxy to create the cookie.
- Port beats subset, and subset beats host.

<!-- astrona:playground:destroy -->
