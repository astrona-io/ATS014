# Where The `DestinationRule` Attaches

> Prerequisite: [The Five-Step Chain](./course-01-the-five-step-chain.md). Next: [Mutual TLS And The Consolidation Argument](./course-03-mutual-tls-and-consolidation.md).

Part 1 asserted that traffic policy is applied by the calling proxy. This part proves it, which also happens to be the cleanest way to verify the whole chain.

## Two independent facts to prove

The response looks identical whether the gateway is involved or not, and whether TLS was originated or not. So there are two separate claims, each with its own evidence:

| Claim | Evidence |
| --- | --- |
| the gateway was in the path | a line in **the gateway's** access log |
| TLS was originated | the destination reports `X-Forwarded-Proto: https`, and the upstream in the log is port **443** |

> [!TIP]
> **Try it — the gateway carried it, and the destination saw HTTPS**
>
> ```sh
> BEFORE=$(kubectl -n istio-system logs deploy/istio-egressgateway --tail=-1 2>/dev/null | grep -c httpbin.org)
> kubectl -n egwtls-demo exec deploy/tester -- \
>   curl -s --max-time 20 http://httpbin.org/headers | grep -i 'X-Forwarded-Proto'
> sleep 3
> AFTER=$(kubectl -n istio-system logs deploy/istio-egressgateway --tail=-1 2>/dev/null | grep -c httpbin.org)
> echo "gateway log lines: +$((AFTER - BEFORE))"
> kubectl -n istio-system logs deploy/istio-egressgateway --tail=10 | grep httpbin.org | tail -1
> ```
>
> Expect something like:
>
> ```text
>     "X-Forwarded-Proto": "https",
> gateway log lines: +1
> [2026-09-27T13:58:12.441Z] "GET /headers HTTP/1.1" 200 - via_upstream - "-" 0 3428 231 230 "10.244.0.33" "curl/8.5.0" "a41f..." "httpbin.org" "34.194.82.45:443" outbound|443||httpbin.org ...
> ```
>
> Three things in that log line worth reading carefully: the request is a **readable HTTP request** (method, path, status), the upstream is port **443**, and the cluster is `outbound|443||httpbin.org`. Together with `X-Forwarded-Proto: https` from the destination, that is the chain confirmed end to end — the application sent HTTP, the gateway sent HTTPS.

## Which proxy holds the TLS context

This is the check that settles arguments, and the one that demonstrates the rule from Part 1 rather than asserting it.

Both proxies are ordinary Envoys and both can be inspected. Only one of them has a TLS transport socket for the external host.

> [!TIP]
> **Try it — the TLS context is on the gateway, not the sidecar**
>
> ```sh
> echo -n "gateway proxy: "
> istioctl proxy-config cluster deploy/istio-egressgateway -n istio-system \
>   --fqdn httpbin.org -o json 2>/dev/null | grep -c transportSocket
> echo -n "tester sidecar: "
> istioctl proxy-config cluster deploy/tester -n egwtls-demo \
>   --fqdn httpbin.org -o json 2>/dev/null | grep -c transportSocket
> ```
>
> Expect something like:
>
> ```text
> gateway proxy: 1
> tester sidecar: 0
> ```
>
> One and zero. The gateway's cluster for the external host carries TLS; the sidecar's does not — because **the sidecar never speaks to `httpbin.org`**. It only speaks to the egress gateway Service, over plain HTTP, and that leg needs no origination.
>
> Compare this with section 070 module 2, where the same two commands would give you `0` and `1`. Same `DestinationRule`, opposite answer, because a different proxy is making the call.

That pair of numbers is the most compact statement of the module's central idea. Traffic policy follows the caller.

## Reading the sidecar's half

For completeness, the sidecar's view confirms it is doing the simpler job:

> [!TIP]
> **Try it — what the sidecar thinks it is talking to**
>
> ```sh
> istioctl proxy-config routes deploy/tester -n egwtls-demo -o json 2>/dev/null \
>   | grep -i '"cluster"' | grep -i egressgateway | head -1
> ```
>
> Expect something like:
>
> ```text
> "cluster": "outbound|80|httpbin|istio-egressgateway.istio-system.svc.cluster.local",
> ```
>
> Port **80**, the gateway Service, the `httpbin` subset. From the sidecar's point of view this is an ordinary in-cluster call to a plain HTTP service. It has no idea TLS is involved anywhere, which is exactly the separation of concerns the arrangement buys.

## A short diagnostic order

When the chain does not work, this sequence resolves it faster than re-reading five objects:

1. **Does the gateway's log show the request at all?**
   - No → the problem is stage 1 or the `Gateway` listener. Check `mesh` in the top-level `gateways`, and the `Gateway`'s `servers[].hosts`.
   - Yes → the hop works; the problem is beyond it.
2. **Does the gateway's log show the upstream as port 443?**
   - No (port 80) → stage 2 is routing to the wrong port.
3. **Does the gateway's cluster for the external host have a `transportSocket`?**
   - No → the origination `DestinationRule` is missing, on the wrong host, or not under `portLevelSettings`.
4. **Does the destination report `X-Forwarded-Proto: https`?**
   - The end-to-end confirmation.

## Keeping it off the sidecars

One detail decides whether that comparison comes out the way this part describes.
A `DestinationRule` is visible mesh-wide by default, so a rule for
`partner.example.com` is handed to **every** sidecar as well as to the gateway —
and each one then builds a TLS-originating cluster for the host. Nothing breaks,
because the sidecars route to the gateway rather than to the host directly and
never use that cluster, but the evidence you are about to rely on is gone: dump
a sidecar and you find a `transportSocket` there too.

Scope the rule to the gateway's namespace so it is handed to the gateway alone:

```yaml
spec:
  exportTo:
    - istio-system
  host: partner.example.com
  trafficPolicy:
    portLevelSettings:
      ...
```

Then the sidecar has no `transportSocket` for the host and the gateway does,
which is both the design you want and the thing you can point at to prove it.

> *`transportSocket` on the gateway and not on the sidecar — that one comparison proves the policy followed the caller.*

## Reference

- [Egress gateway TLS origination](https://istio.io/latest/docs/tasks/traffic-management/egress/egress-gateway-tls-origination/) — the verification steps in the upstream task.
- [Debugging Envoy and istiod](https://istio.io/latest/docs/ops/diagnostic-tools/proxy-cmd/) — `proxy-config` against a gateway as well as a sidecar.
- [TrafficPolicy](https://istio.io/latest/docs/reference/config/networking/destination-rule/#TrafficPolicy) — the object whose scope this part is about.
- `istioctl proxy-config cluster <workload> --fqdn <host> -o json` — run it against both proxies; the difference is the lesson.
