# Summary

Locality load balancing keeps requests close to the client, and locality failover moves them further away when the nearby endpoints fail. Both depend on every endpoint, and the client pod itself, having a locality.

An endpoint's locality comes from the labels of the node that runs the pod: `topology.kubernetes.io/region`, `topology.kubernetes.io/zone` and the optional `topology.istio.io/subzone`. The `istio-locality` label on a pod template overrides the node's locality for that pod. Its value uses dots, such as `local.zone-b`, because a label value cannot contain a slash. Istio reads it when the pod starts, so a change needs new pods.

Before you configure anything, read the localities from the client's sidecar proxy with `istioctl proxy-config endpoints ... -o json`. An endpoint without a locality makes every locality setting do nothing, and no error message says so.

The locality preference only acts on a host whose `DestinationRule` has `outlierDetection`. `localityLbSetting: {enabled: true}` on its own changes nothing. With outlier detection, `istiod` gives the endpoints in other zones `"priority": 1`, and the proxy only uses them when the client's own zone has no healthy endpoint left.

`distribute` replaces the preference with fixed weights for clients in a given locality. The weights must add up to exactly 100, and they work without outlier detection. `failover` names the next region, needs outlier detection, and cannot be combined with `distribute` for the same host.

A zone can lose its endpoints in two ways. When a pod is removed, Kubernetes takes it out of the endpoint list, and requests move without errors. When a pod fails but stays ready, only outlier detection notices: after `consecutive5xxErrors` errors in a row, the proxy ejects the endpoint, and `istioctl proxy-config endpoints` shows `FAILED` in its `OUTLIER CHECK` column. A failover test must use a failing pod, not a pod scaled to zero.

Key facts to remember:

- `maxEjectionPercent` defaults to 10%, which cannot eject one of two or three endpoints; raise it, for example to `100`.
- `distribute` and `failover` use slashes (`local/zone-a/*`); only the `istio-locality` label uses dots.
- `failover` works between regions; moving between zones inside a region is the preference itself.
- `meshConfig.localityLbSetting` sets the mesh-wide default at install time; a `DestinationRule` overrides it for one host.

<!-- astrona:playground:destroy -->
