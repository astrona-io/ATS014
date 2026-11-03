# Solution

This walkthrough follows the task from top to bottom. Each section ends with a check. Items 1 and 2 are two separate mistakes in one object; you fix them in one file, and the later sections prove the result.

## Start

Set the address the helper scripts use, read the starting `DestinationRule`, and send requests:

```sh
HOSTNAME_URL=http://probe:8000/hostname
kubectl get destinationrule probe -n starfleet -o yaml
astrona res run status-codes.sh -- -H "x-user: alice" $HOSTNAME_URL
```

The `DestinationRule` has `tls: mode: DISABLE` at the top level, and subset `v2` has `loadBalancer: simple: ROUND_ROBIN`. The requests return `503` instead of `200`. Read the `shuttle` proxy's access log to see the failed requests:

```sh
kubectl logs deploy/shuttle -n starfleet -c istio-proxy --tail=5
```

The log lines show status `503` for the cluster `outbound|8000|v1|probe.starfleet.svc.cluster.local`. The `DISABLE` mode makes the `shuttle` pod's proxy send plain text, and the `probe` pods accept only mTLS because of the `PeerAuthentication`, so they reset the connection.

## Item 1: remove DISABLE

> **Task item 1:** It contains no `tls.mode: DISABLE` anywhere. The client TLS setting either is removed, or is `ISTIO_MUTUAL`.

With no `tls` block, automatic mTLS makes the proxy use mTLS to the probe pods, because they have a sidecar. Setting `ISTIO_MUTUAL` says the same thing explicitly. This walkthrough sets it. The change to item 2 goes in the same file, so the full object is shown under item 2.

## Item 2: stop the subset from replacing the load balancer

> **Task item 2:** The host-level `loadBalancer.consistentHash` on the header `x-user` stays, and no subset sets `loadBalancer.simple`. Both subsets `v1` and `v2` stay defined.

A subset that sets `loadBalancer` replaces the host's whole `loadBalancer` field for that subset. Subset `v2` set `simple: ROUND_ROBIN`, so the host's `consistentHash` no longer applied to it, and Istio did not report any error. The fix is to remove the subset's `trafficPolicy` and let the subset inherit the host's.

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
    loadBalancer:
      consistentHash:
        httpHeaderName: x-user
    tls:
      mode: ISTIO_MUTUAL
  subsets:
  - name: v1
    labels:
      version: v1
  - name: v2
    labels:
      version: v2
```

Apply it:

```sh
kubectl apply -f destinationrule-probe.yaml
```

Check the object for the two changes:

```sh
kubectl get destinationrule probe -n starfleet -o yaml | grep -E 'mode|simple|httpHeaderName'
```

The output shows `ISTIO_MUTUAL` and `x-user`. It shows no `DISABLE` and no `simple`.

## Item 3: the proxy holds the settings

> **Task item 3:** The `shuttle` pod's proxy holds a TLS transport socket and the `lbPolicy` `RING_HASH` for both subset clusters of `probe`.

Wait a few seconds for `istiod` to send the configuration, then print each subset cluster:

```sh
istioctl proxy-config cluster deploy/shuttle -n starfleet --fqdn probe.starfleet.svc.cluster.local --subset v1 -o json | grep -E 'transport_sockets.tls|lbPolicy'
istioctl proxy-config cluster deploy/shuttle -n starfleet --fqdn probe.starfleet.svc.cluster.local --subset v2 -o json | grep -E 'transport_sockets.tls|lbPolicy'
```

Both clusters show `envoy.transport_sockets.tls` and `"lbPolicy": "RING_HASH"`. Before the fix, the `v2` cluster did not show `RING_HASH`.

## Item 4: live requests

> **Task item 4:** Eight requests with the header `x-user: alice` return status `200` and are answered by one `probe-v1` pod. Eight requests with `x-user: alice` and `x-canary: true` return status `200` and are answered by one `probe-v2` pod.

```sh
astrona res run status-codes.sh -- -H "x-user: alice" $HOSTNAME_URL
astrona res run count-pods.sh -- -H "x-user: alice" $HOSTNAME_URL
astrona res run count-pods.sh -- -H "x-user: alice" -H "x-canary: true" $HOSTNAME_URL
```

The status count shows eight `200` answers. Each pod count shows one pod name with the count `8`: one `probe-v1-` pod for the first and one `probe-v2-` pod for the second.

## Item 5: leave the rest alone

> **Task item 5:** The `PeerAuthentication` stays `STRICT` and the workloads stay as they are. The `drifter` pod must still not get a `200` from the `probe`.

You did not touch them. Prove it:

```sh
kubectl get peerauthentication probe -n starfleet -o jsonpath='{.spec.mtls.mode}'
astrona res run drifter-call.sh
```

The mode is `STRICT`. The `drifter` does not get `200`; the code is usually `000`.

## Submit

```sh
astrona submit -c sections/section-030/module-02/labs/lab-02
```

## Mistakes That Fail The Grader

- **Item 1:** changing the `PeerAuthentication` to `PERMISSIVE` instead of fixing the client. The `DestinationRule` must match `STRICT`.
- **Item 1:** replacing `DISABLE` with `SIMPLE` or `MUTUAL`. They send no certificate that the probe accepts, so the requests still fail. Use `ISTIO_MUTUAL` or no `tls` block.
- **Item 2:** fixing only the TLS mode. The requests return `200`, but subset `v2` still spreads `alice` over both pods.
- **Item 2:** deleting the `DestinationRule`. The `VirtualService` needs the subsets `v1` and `v2`.
- **Item 2:** removing the host-level `consistentHash` instead of the subset's `ROUND_ROBIN`.
- **Item 3:** checking the proxy before `istiod` has sent the new configuration. Wait a few seconds and submit again.
