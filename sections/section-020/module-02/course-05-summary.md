# Summary

Mirroring sends a copy of each request to a second destination, the shadow, while the normal route keeps sending the response. In a `VirtualService`, `mirror` sits next to `route` on the same `http` rule. It is one destination with no `weight`, so it is never part of a weighted split. The copy is extra traffic on top: a full mirror doubles the number of requests inside the cluster.

The sidecar proxy of the client pod sends the copy. It waits only for the route's response and throws the shadow's response away, together with any delay. So the client never sees what the shadow returns. A shadow that returns `503` to every copy looks exactly like a healthy one from the client's side, and only the shadow's own logs show the failure.

Istio 1.30 sends the copy unchanged. Older releases added `-shadow` to the host name, but you cannot rely on that suffix today. The proof that a mirror works is on the receiving side. When the route sends nothing to the shadow, every request in the shadow's access log is a copy. It arrives through the mirror subset and carries the same request ID as the original in the client's access log.

`mirrorPercentage` copies a random share of the matched requests. If you leave it out, the share is 100%, not 0%. The proxy decides for each request on its own, so count at least 100 requests before you judge the share. A `match` block is different: it copies a specific kind of request, not a random sample.

A mirror can stay quiet while the client is fine. The client's proxy holds the mirror as `requestMirrorPolicies` in its route table, with the share stored as a fraction of a million. A quiet mirror has one of three causes: no mirror policy in the proxy, a policy that names a subset no `DestinationRule` defines, or a subset whose labels match no pod. The mirror policy, the endpoints of the mirror cluster and `istioctl analyze` together tell these causes apart.

The shadow does real work. Database writes, messages and payments really happen, and only the response is thrown away. Nothing in the copy tells the shadow that it is a copy, so give the shadow its own datastore and its own Service before you mirror anything with side effects. Mirroring finds crashes and load problems, but it cannot compare responses.

Key facts to remember:

- `mirror` and `mirrorPercentage` are siblings of `route`; `mirrors` is the plural form for several shadows.
- The default `mirrorPercentage` is 100%.
- With a split plus a mirror, the mirror target receives its own share plus a copy of every request.
- `IST0101` means the mirror subset is not defined; `IST0173` means the subset selects no pods.

<!-- astrona:playground:destroy -->
