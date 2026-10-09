# Summary

Weighted routing sends a set share of requests to each version of a Service. In a `VirtualService`, one `http` rule lists several destinations, and each destination gets a `weight`. The `weight` field sits next to `destination`, not inside it. With one destination you can leave it out, and it counts as 100.

The sidecar proxy of the sending pod makes one random pick for each request, with the weights as the odds. The split is not a fixed rotation, so it only shows up over many requests and is never exact. Ten requests tell you almost nothing; count at least 100 before you trust a split.

Istio 1.30.5 accepts weights that do not add up to 100 and uses them as a ratio, so 50 and 30 give about 62/38. A destination with `weight: 0` stays in your YAML, but `istiod` leaves it out of the proxy's route. A weight on a subset that no `DestinationRule` defines is accepted too, and the requests sent there fail with `503`. Only `istioctl analyze` reports it, with the code `IST0101`.

A canary release is the same `VirtualService` applied again with new numbers. `istiod` pushes each change to the proxies within seconds, and no pod restarts. A rollback is the old numbers, applied again. A merge patch on `spec.http` replaces the whole list, so it must restate every rule. A header match placed above the weighted rule takes its requests out of the split, because the first rule that matches wins.

The proxy picks the subset first and only then picks a pod inside it with load balancing. So weights control traffic share, and replicas control capacity. Four v1 pods against one v3 pod still split 50/50. To see the weights a proxy really uses, read the `weightedClusters` block from `istioctl proxy-config routes`.

Key facts to remember:

- Write weights that add up to 100, inside one route list of one `http` rule.
- Count at least 100 requests before you judge a split.
- Run `istioctl analyze` after every weight change.
- A cluster name such as `outbound|9080|v1|scout.starfleet.svc.cluster.local` gives the direction, the port, the subset and the host.

<!-- astrona:playground:destroy -->
