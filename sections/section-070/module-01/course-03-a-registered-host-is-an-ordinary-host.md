# A Registered Host Is An Ordinary Host

> Prerequisite: [The `ServiceEntry` Object](./course-02-the-serviceentry-object.md). Next: [the module landing page](./course.md).

This is what makes `ServiceEntry` more than an allow-list, and it is the part that pays back everything you learned in sections 010 to 050. Then two scoping behaviours that decide whether the object works where you expect it to.

## Everything from earlier sections now applies

Once `httpbin.org` is in the registry, it behaves like any other host in the mesh:

| Section | What you can now do to somebody else's API |
| --- | --- |
| 010 | route different paths to different destinations |
| 040 | set a `timeout` and a retry policy |
| 040 | apply a connection pool, so a slow partner cannot exhaust your workers |
| 040 | apply outlier detection across its resolved addresses |
| 030 | set a load balancer policy |
| 050 | inject a fault, to test how your code handles that API failing |

None of this requires cooperation from the external service. It is all client-side, enforced in your own sidecar.

The timeout is the clearest demonstration, and the most immediately useful: a deadline on a third-party API you do not control and cannot change.

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: httpbin-ext
  namespace: egress-demo
spec:
  hosts:
    - httpbin.org
  http:
    - timeout: 2s
      route:
        - destination:
            host: httpbin.org
```

This works **only because** the `ServiceEntry` declared `protocol: HTTP`. With a `TCP` port the proxy has no idea where one request ends and the next begins, so there is nothing for a `timeout` to bound — the `VirtualService` would apply to nothing.

> [!TIP]
> **Try it — a deadline on somebody else's API**
>
> ```sh
> kubectl apply -f - <<'EOF'
> apiVersion: networking.istio.io/v1
> kind: VirtualService
> metadata:
>   name: httpbin-ext
>   namespace: egress-demo
> spec:
>   hosts:
>     - httpbin.org
>   http:
>     - timeout: 2s
>       route:
>         - destination:
>             host: httpbin.org
> EOF
> sleep 3
> kubectl -n egress-demo exec deploy/tester -- \
>   curl -s -o /dev/null -w 'delay/5: %{http_code} in %{time_total}s\n' --max-time 20 http://httpbin.org/delay/5
> kubectl -n egress-demo logs deploy/tester -c istio-proxy --tail=2 | grep -E 'UT|504' | head -1
> ```
>
> Expect something like:
>
> ```text
> delay/5: 504 in 2.048s
> [2026-09-27T14:02:11.771Z] "GET /delay/5 HTTP/1.1" 504 UT upstream_response_timeout ...
> ```
>
> Two seconds, not five, with the `UT` flag from section 040 — the same mechanism, applied to a host on the public internet. That is the payoff for putting it in the registry.

A `DestinationRule` works the same way, and is arguably more valuable in production: a connection pool on an external dependency stops a slow partner API from filling your workers.

> [!TIP]
> **Try it — a connection pool on an external host**
>
> ```sh
> kubectl apply -f - <<'EOF'
> apiVersion: networking.istio.io/v1
> kind: DestinationRule
> metadata:
>   name: httpbin-ext
>   namespace: egress-demo
> spec:
>   host: httpbin.org
>   trafficPolicy:
>     connectionPool:
>       tcp:
>         maxConnections: 2
>       http:
>         http1MaxPendingRequests: 2
> EOF
> sleep 3
> istioctl proxy-config cluster deploy/tester -n egress-demo --fqdn httpbin.org -o json \
>   | grep -A5 circuitBreakers
> ```
>
> Expect something like:
>
> ```text
> "circuitBreakers": {
>   "thresholds": [
>     {
>       "maxConnections": 2,
>       "maxPendingRequests": 2,
> ```
>
> A `DestinationRule` pointing at a public hostname, compiled into exactly the same Envoy circuit breaker as section 040 module 2 produced for an in-cluster Service. The object does not know or care that the destination is external.

## `exportTo` — a namespaced object with mesh-wide reach

A `ServiceEntry` is namespaced, but by **default it is exported to the entire mesh**. Every namespace can use it.

That surprises people, and it matters: a `ServiceEntry` created in one team's namespace opens that host for everybody. `exportTo` narrows it:

```yaml
spec:
  exportTo:
    - "."          # this namespace only
```

The values are the same shorthand as elsewhere: `.` for the object's own namespace, `*` for everywhere (the default), or a list of namespace names.

For a `REGISTRY_ONLY` mesh where the point is control, `exportTo: ["."]` on every `ServiceEntry` is a reasonable default — otherwise one namespace's allow-list is silently everyone's.

## The `Sidecar` interaction

This is the diagnostic worth carrying out of the module, because the symptom is identical to a missing `ServiceEntry`.

Section 010's `Sidecar` resource limits which registry entries a proxy is programmed with — and Part 1 noted the registry includes `ServiceEntry` hosts. So a perfectly correct, mesh-exported `ServiceEntry` can be **invisible** to one namespace because that namespace's `Sidecar` never listed the external host in its `egress.hosts`.

The result is a 502, exactly as if the host had never been registered.

```text
  external call fails with 502
            │
            ├─ ServiceEntry exists?  ── no ──► create it
            │        yes
            ├─ exportTo allows this namespace? ── no ──► widen it
            │        yes
            └─ a Sidecar in this namespace? ── yes ──► is the host in egress.hosts?
                                                            no ──► that is the cause
```

The rule of thumb: **when a `ServiceEntry` works from one namespace and not another, look for a `Sidecar` before re-reading the `ServiceEntry`.**

## Common pitfalls

> [!WARNING]
> **Expecting `REGISTRY_ONLY` without setting it.** The default is `ALLOW_ANY`. If external calls succeed before you create any `ServiceEntry`, the mode is why.
>
> **Reading the 502 as a network problem.** Under `REGISTRY_ONLY` a 502 from the sidecar means "not in the registry". DNS and connectivity are fine.
>
> **Declaring `protocol: TCP` and expecting HTTP features.** No timeouts, no retries, no path routing. The declared protocol is what enables layer-7 handling.
>
> **Registering only the port the application uses today.** A `ServiceEntry` for port 80 does nothing for an HTTPS call on 443 — which is module 2's whole subject.
>
> **Assuming a `ServiceEntry` is namespace-private.** It is exported mesh-wide unless `exportTo` says otherwise.
>
> **Overlooking a `Sidecar` scope.** It hides a perfectly good `ServiceEntry` from one namespace, with the same 502 you would get from never having created it.
>
> **Using `resolution: DNS` with a wildcard host.** There is no single name to resolve; use `NONE`.
>
> **Forgetting the proxy resolves the name, not you.** With `resolution: DNS` the hostname must resolve from inside the pod.

> *A registered external host is an ordinary mesh host — every `VirtualService` and `DestinationRule` feature in this course applies to it unchanged.*

## Reference

- [ServiceEntry API](https://istio.io/latest/docs/reference/config/networking/service-entry/) — including `exportTo` and its defaults.
- [Accessing external services](https://istio.io/latest/docs/tasks/traffic-management/egress/egress-control/) — the timeout-on-an-external-host example.
- [Sidecar API](https://istio.io/latest/docs/reference/config/networking/sidecar/) — the object that can hide a `ServiceEntry`, from section 010.
- `istioctl proxy-config cluster <workload> --fqdn <host>` — whether this proxy can see this host at all.
