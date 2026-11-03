# Solution

This walkthrough follows the task from top to bottom. Items 1 to 3 are one `DestinationRule`, so you write them together in one file, and each later section ends with a check.

## Start

Set the address the helper scripts use, then look at the starting state:

```sh
HOSTNAME_URL=http://probe:8000/hostname
kubectl get peerauthentication,virtualservice,destinationrule -n starfleet
astrona res run status-codes.sh -- $HOSTNAME_URL
```

The `PeerAuthentication` and the `VirtualService` exist, and there is no `DestinationRule`. All eight requests return an error status, not `200`, because the `VirtualService` sends them to subset `v1`, and that subset is not defined yet. Without a defined subset the proxy has no cluster to send the request to.

## Items 1, 2 and 3: the DestinationRule

> **Task item 1:** Its host is `probe`, and it defines the subsets `v1` (pods labelled `version: v1`) and `v2` (pods labelled `version: v2`).
>
> **Task item 2:** The host-level `trafficPolicy.tls.mode` is `ISTIO_MUTUAL`. The `DestinationRule` has no `DISABLE` anywhere.
>
> **Task item 3:** Subset `v2` has its own `trafficPolicy` with `loadBalancer.simple: RANDOM`. Subset `v1` sets no load balancer.

The `PeerAuthentication` makes the probe pods accept only mTLS. The matching client setting is `tls.mode: ISTIO_MUTUAL`: the `shuttle` pod's proxy then opens its connections with mTLS and the certificates that `istiod` gives it. A subset inherits the host's `tls` block when it does not set its own, so subset `v2` only needs its `loadBalancer`.

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
  subsets:
  - name: v1
    labels:
      version: v1
  - name: v2
    labels:
      version: v2
    trafficPolicy:
      loadBalancer:
        simple: RANDOM
```

Apply it:

```sh
kubectl apply -f destinationrule-probe.yaml
```

Check that the object exists with both subsets:

```sh
kubectl get destinationrule probe -n starfleet -o jsonpath='{.spec.subsets[*].name}'
```

## Item 4: the proxy holds the settings

> **Task item 4:** The `shuttle` pod's proxy holds a TLS transport socket for both subset clusters of `probe`, and the `lbPolicy` `RANDOM` for the `v2` cluster only.

`istiod` needs a moment to send the new configuration to the `shuttle` pod's proxy. Print the `v2` cluster, then the `v1` cluster, and look for the TLS transport socket and the policy:

```sh
istioctl proxy-config cluster deploy/shuttle -n starfleet --fqdn probe.starfleet.svc.cluster.local --subset v2 -o json | grep -E 'transport_sockets.tls|lbPolicy'
istioctl proxy-config cluster deploy/shuttle -n starfleet --fqdn probe.starfleet.svc.cluster.local --subset v1 -o json | grep -E 'transport_sockets.tls|lbPolicy'
```

Both clusters show the name `envoy.transport_sockets.tls`. Only the `v2` cluster shows `"lbPolicy": "RANDOM"`.

## Item 5: live requests

> **Task item 5:** Eight requests from the `shuttle` pod to `http://probe:8000/hostname` without extra headers return status `200` and are answered by `probe-v1` pods. Eight requests with the header `x-canary: true` return status `200` and are answered by the `probe-v2` pod.

Count the status codes and the answering pods for both kinds of request:

```sh
astrona res run status-codes.sh -- $HOSTNAME_URL
astrona res run count-pods.sh -- $HOSTNAME_URL
astrona res run status-codes.sh -- -H "x-canary: true" $HOSTNAME_URL
astrona res run count-pods.sh -- -H "x-canary: true" $HOSTNAME_URL
```

The status count shows eight `200` answers each time. The pod names without the header all start with `probe-v1-` and may be spread over the three pods. With the header, the only name is the `probe-v2-` pod.

## Item 6: leave the rest alone

> **Task item 6:** The `PeerAuthentication` stays `STRICT` and the workloads stay as they are. The `drifter` pod must still not get a `200` from the `probe`.

You changed nothing else, so this item needs no work. Prove it from the `drifter`, which has no sidecar proxy and so cannot send mTLS:

```sh
kubectl get peerauthentication probe -n starfleet -o jsonpath='{.spec.mtls.mode}'
astrona res run drifter-call.sh
```

The mode is `STRICT`. The `drifter` does not get `200`. The code is usually `000`, which means the connection was refused or reset and curl got no HTTP response.

## Submit

```sh
astrona submit -c sections/section-030/module-02/labs/lab-01
```

## Mistakes That Fail The Grader

- **Item 2:** setting `tls.mode: DISABLE`, or `SIMPLE`. `DISABLE` sends plain text to a pod that accepts only mTLS, and `SIMPLE` sends no client certificate. Both fail the live requests. The grader wants `ISTIO_MUTUAL`.
- **Item 2:** putting `tls` only in subset `v2`. Then subset `v1` has no explicit client TLS mode and the host-level mode is missing.
- **Item 3:** setting a load balancer on subset `v1` too, or on the host. Only subset `v2` gets `RANDOM`.
- **Items 1 and 5:** wrong subset labels. A subset that selects no pods gives no endpoints, and the requests fail.
- **Item 6:** changing the `PeerAuthentication` to `PERMISSIVE` to make the calls work. The `DestinationRule` must match `STRICT`, not weaken it.
