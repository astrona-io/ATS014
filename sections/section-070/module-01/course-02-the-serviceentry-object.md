# The `ServiceEntry` Object

> Prerequisite: [The Outbound Traffic Policy](./course-01-the-outbound-traffic-policy.md). Next: [A Registered Host Is An Ordinary Host](./course-03-a-registered-host-is-an-ordinary-host.md).

Four fields, each answering one question. This part is what each decides, and why one of them gates everything the rest of the course can do with an external host.

## The object

```yaml
apiVersion: networking.istio.io/v1
kind: ServiceEntry
metadata:
  name: httpbin-ext
  namespace: egress-demo
spec:
  hosts:
    - httpbin.org
  ports:
    - number: 80
      name: http
      protocol: HTTP
  location: MESH_EXTERNAL
  resolution: DNS
```

| Field | Answers |
| --- | --- |
| `hosts` | what is it called? |
| `ports` | on which port, speaking what? |
| `location` | is it ours or somebody else's? |
| `resolution` | how does the proxy find an address for it? |

## `hosts`

The DNS names this entry covers. Wildcards are allowed — `*.example.com` registers the whole subdomain, which is how you cover a service whose hostnames you cannot enumerate.

One subtlety: for `resolution: DNS`, the host must be a name the **proxy** can resolve. It is resolved from inside the pod, using the cluster's DNS, so a name that only resolves on your laptop will not work.

## `ports` — and why `protocol` is the important word

Each entry is a number, a name, and a **protocol**. The protocol is what decides how much of Istio applies:

| `protocol` | The proxy will |
| --- | --- |
| `HTTP` | parse requests — so `VirtualService` rules, timeouts, retries, per-path routing and useful telemetry all work |
| `HTTPS` | treat it as an opaque TLS stream (unless you originate TLS yourself — module 2) |
| `TLS` | inspect SNI only |
| `TCP` | move bytes, with no layer-7 awareness at all |
| `GRPC`, `MONGO`, `MYSQL`, … | protocol-specific handling |

Declaring `TCP` when the traffic is HTTP is not an error and produces a working connection — with none of the features you probably wanted. The symptom is a `VirtualService` on that host doing nothing at all, which is a confusing thing to debug backwards.

The `name` matters too, though less obviously: Istio uses the port name as a fallback protocol hint in some contexts, so naming a port `http` and declaring it `TCP` is a contradiction worth avoiding.

## `location` — `MESH_EXTERNAL` or `MESH_INTERNAL`

| Value | Means | Use for |
| --- | --- | --- |
| `MESH_EXTERNAL` | not part of the mesh | a third party's API — this module |
| `MESH_INTERNAL` | part of the mesh, just not in Kubernetes | a VM you run — module 3 |

The difference is not cosmetic. `MESH_INTERNAL` tells Istio to treat the endpoints as mesh members, which brings mutual TLS and workload identity into play. `MESH_EXTERNAL` gives you routing and policy but no identity — which is correct, because you do not issue certificates to somebody else's API.

For a third-party service, `MESH_EXTERNAL` is the answer, and it is the default.

## `resolution` — how an address is found

| Value | The proxy | Use with |
| --- | --- | --- |
| `DNS` | resolves the hostname itself and keeps the result fresh | a public hostname |
| `STATIC` | uses the addresses listed in `endpoints` | fixed IPs, or `WorkloadEntry` selection (module 3) |
| `NONE` | passes the original destination address through unresolved | a destination that resolves itself, or a wildcard host |
| `DNS_ROUND_ROBIN` | resolves lazily and uses one address at a time | an endpoint behind a load balancer where you want connection affinity to a single resolved IP |

`DNS` is right for nearly every public API. `NONE` is what you use with a wildcard host, because there is nothing concrete to resolve.

> [!TIP]
> **Try it — register one host, leave the rest blocked**
>
> ```sh
> kubectl apply -f - <<'EOF'
> apiVersion: networking.istio.io/v1
> kind: ServiceEntry
> metadata:
>   name: httpbin-ext
>   namespace: egress-demo
> spec:
>   hosts:
>     - httpbin.org
>   ports:
>     - number: 80
>       name: http
>       protocol: HTTP
>   location: MESH_EXTERNAL
>   resolution: DNS
> EOF
> sleep 3
> kubectl -n egress-demo exec deploy/tester -- \
>   curl -s -o /dev/null -w 'httpbin.org:  %{http_code}\n' --max-time 10 http://httpbin.org/get
> kubectl -n egress-demo exec deploy/tester -- \
>   curl -s -o /dev/null -w 'example.com:  %{http_code}\n' --max-time 10 http://example.com/
> ```
>
> Expect something like:
>
> ```text
> serviceentry.networking.istio.io/httpbin-ext created
> httpbin.org:  200
> example.com:  502
> ```
>
> One host allowed, everything else still refused. That pair of results is the whole point of `REGISTRY_ONLY` plus `ServiceEntry`: egress becomes a list you maintain rather than an assumption you inherit.

## Confirming registration

A registered external host gets a cluster in every proxy allowed to see it, exactly like an in-cluster Service. This is the check that answers "is this host registered for this workload?" without sending traffic.

> [!TIP]
> **Try it — the external host in the proxy's cluster list**
>
> ```sh
> istioctl proxy-config cluster deploy/tester -n egress-demo | grep -iE 'httpbin.org|example.com' || echo "(no match)"
> ```
>
> Expect something like:
>
> ```text
> httpbin.org     80     -     outbound     STRICT_DNS
> ```
>
> `STRICT_DNS` is Envoy's discovery type for `resolution: DNS` — the proxy resolves the name itself and refreshes it. `example.com` is absent, which is exactly why it 502s. Compare the discovery type here with the `EDS` you saw for in-cluster Services in section 010: different mechanisms, same cluster abstraction.

## Wildcards

For a service whose hostnames you cannot list — a CDN, an object store with per-bucket names — a wildcard plus `resolution: NONE` is the shape:

```yaml
spec:
  hosts:
    - "*.amazonaws.com"
  ports:
    - number: 443
      name: https
      protocol: TLS
  location: MESH_EXTERNAL
  resolution: NONE
```

`NONE` because there is no single name to resolve; the proxy forwards to whatever address the client already determined. `TLS` because SNI is the only thing it can meaningfully inspect. This is broad — it permits every host under that suffix — so it is a deliberate trade of precision for practicality, not a default.

> *The declared `protocol` decides how much of Istio applies to an external host; `TCP` gets you a working connection and nothing else.*

## Reference

- [ServiceEntry API](https://istio.io/latest/docs/reference/config/networking/service-entry/) — every field, including `endpoints`, `exportTo` and `workloadSelector`.
- [Accessing external services](https://istio.io/latest/docs/tasks/traffic-management/egress/egress-control/) — the upstream walkthrough this module follows.
- [Protocol selection](https://istio.io/latest/docs/ops/configuration/traffic-management/protocol-selection/) — how Istio decides a port's protocol, including the port-name convention.
- `istioctl proxy-config cluster <workload>` — the one command that confirms a host is registered for a given proxy.
