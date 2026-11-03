# Solution

This walkthrough follows the task from top to bottom. Items 1 to 4 are one `DestinationRule`, so you write them together in one file. Each later section ends with a check.

## Start

Set the address the helper scripts use and look at the starting state:

```sh
HOSTNAME_URL=http://probe:8000/hostname
kubectl get peerauthentication,virtualservice,destinationrule -n starfleet
astrona res run status-codes.sh -- $HOSTNAME_URL
```

The `PeerAuthentication` and the `VirtualService` exist, and there is no `DestinationRule`. The requests fail, because the `VirtualService` sends them to subsets that are not defined yet.

## Items 1 to 4: the DestinationRule

> **Task item 1:** Its host is `probe`, and it defines the subsets `v1` and `v2`.
>
> **Task item 2:** The host-level `trafficPolicy.tls.mode` is `ISTIO_MUTUAL`, and the `DestinationRule` has no `DISABLE` anywhere.
>
> **Task item 3:** The host-level `trafficPolicy.loadBalancer` is a `consistentHash` on the header `x-session-id`.
>
> **Task item 4:** Subset `v2` has its own `loadBalancer.simple: ROUND_ROBIN`. No other `simple` setting exists in the `DestinationRule`, and subset `v1` sets no `trafficPolicy`.

The host-level `trafficPolicy` carries both the TLS mode and the load balancer. Subset `v1` sets nothing, so it inherits both. Subset `v2` sets only `loadBalancer`, which replaces the host's `loadBalancer` for `v2`, and it still inherits the host's `tls`, so mTLS keeps working for `v2`.

Save this as `destinationrule-probe.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: probe
  namespace: starfleet
spec:
  host: probe
  trafficPolicy:
    tls:
      mode: ISTIO_MUTUAL
    loadBalancer:
      consistentHash:
        httpHeaderName: x-session-id
  subsets:
  - name: v1
    labels:
      version: v1
  - name: v2
    labels:
      version: v2
    trafficPolicy:
      loadBalancer:
        simple: ROUND_ROBIN
```

Apply it:

```sh
kubectl apply -f destinationrule-probe.yaml
```

Check the object:

```sh
kubectl get destinationrule probe -n starfleet -o yaml | grep -E 'mode|simple|httpHeaderName|name: v'
```

## Item 5: the proxy holds the settings

> **Task item 5:** The `shuttle` pod's proxy holds a TLS transport socket for both subset clusters, the `lbPolicy` `RING_HASH` for the `v1` cluster, and no `RING_HASH` for the `v2` cluster.

Wait a few seconds for `istiod` to send the configuration, then print each subset cluster:

```sh
istioctl proxy-config cluster deploy/shuttle -n starfleet --fqdn probe.starfleet.svc.cluster.local --subset v1 -o json | grep -E 'transport_sockets.tls|lbPolicy'
istioctl proxy-config cluster deploy/shuttle -n starfleet --fqdn probe.starfleet.svc.cluster.local --subset v2 -o json | grep -E 'transport_sockets.tls|lbPolicy'
```

Both clusters show `envoy.transport_sockets.tls`. The `v1` cluster shows `"lbPolicy": "RING_HASH"`. The `v2` cluster does not show `RING_HASH`: round robin is Envoy's default, so it prints no `lbPolicy` line at all.

## Item 6: live requests

> **Task item 6:** Eight requests with the header `x-session-id: s1` return status `200` and are answered by one `probe-v1` pod. Eight requests with `x-session-id: s1` and `x-canary: true` return status `200` and reach both `probe-v2` pods.

```sh
astrona res run status-codes.sh -- -H "x-session-id: s1" $HOSTNAME_URL
astrona res run count-pods.sh -- -H "x-session-id: s1" $HOSTNAME_URL
astrona res run count-pods.sh -- -H "x-session-id: s1" -H "x-canary: true" $HOSTNAME_URL
```

The status count shows eight `200` answers. The first pod count shows one `probe-v1-` pod name with the count `8`. The second shows both `probe-v2-` pods.

## Item 7: leave the rest alone

> **Task item 7:** The `PeerAuthentication` stays `STRICT` and the workloads stay as they are. The `drifter` pod must still not get a `200` from the `probe`.

```sh
kubectl get peerauthentication probe -n starfleet -o jsonpath='{.spec.mtls.mode}'
astrona res run drifter-call.sh
```

The mode is `STRICT`. The `drifter` does not get `200`; the code is usually `000`.

## Submit

```sh
astrona submit -c sections/section-030/capstone/labs/lab-02
```

## Mistakes That Fail The Grader

- **Items 2 and 5:** `DISABLE`, `SIMPLE` or `MUTUAL` as the client mode. The probe accepts only mTLS from the mesh, so the requests fail. Use `ISTIO_MUTUAL`.
- **Items 3 and 4:** setting `simple: ROUND_ROBIN` at host level. Then `v1` is not sticky.
- **Item 4:** giving subset `v1` a `trafficPolicy`, or adding a second `simple` setting.
- **Item 6:** hashing a different header, for example `x-user`. The grader sends `x-session-id`.
- **Item 7:** changing the `PeerAuthentication` to `PERMISSIVE` to make the calls work.
