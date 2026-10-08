# The `ServiceEntry` Object

A `ServiceEntry` adds a planet from another solar system to the star chart (the service registry). It has four fields, each answering one question. This part is what each decides, and why one of them gates everything the rest of the course can do with an external host.

## The object

```yaml
apiVersion: networking.istio.io/v1
kind: ServiceEntry
metadata:
  name: httpbin-org
  namespace: bookinfo
spec:
  hosts:
    - httpbin.org
  ports:
    - number: 443
      name: https
      protocol: HTTPS
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

Each entry is a number (think of it as a radio channel), a name, and a **protocol**. The protocol tells the communications officer what language the signals on that channel speak, and that decides how much of Istio applies:

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

The difference is not cosmetic. `MESH_INTERNAL` tells Istio to treat the endpoints as mesh members, which brings mutual TLS and workload identity into play. `MESH_EXTERNAL` gives you routing and policy but no identity — which is correct, because you do not issue certificates to somebody else's API. mTLS (mutual TLS) is a secret handshake that both ships check before they talk, and a planet in another solar system does not know Istio's handshake.

For a third-party service, `MESH_EXTERNAL` is the answer, and it is the default.

## `resolution` — how an address is found

| Value | The proxy | Use with |
| --- | --- | --- |
| `DNS` | resolves the hostname itself and keeps the result fresh | a public hostname |
| `STATIC` | uses the addresses listed in `endpoints` | fixed IPs, or `WorkloadEntry` selection (module 3) |
| `NONE` | passes the original destination address through unresolved | a destination that resolves itself, or a wildcard host |
| `DNS_ROUND_ROBIN` | resolves lazily and uses one address at a time | an endpoint behind a load balancer where you want connection affinity to a single resolved IP |

`DNS` is right for nearly every public API. `NONE` is what you use with a wildcard host, because there is nothing concrete to resolve.

<!-- astrona:playground:renew -->

> [!TIP]
> **Try it — `httpbin.org` allowed over HTTPS only**
>
> This builds on the `REGISTRY_ONLY` `Sidecar` from Part 1.
>
> Save this as `serviceentry-httpbin-org.yaml`:
>
> ```yaml
> apiVersion: networking.istio.io/v1
> kind: ServiceEntry
> metadata:
>   name: httpbin-org
>   namespace: bookinfo
> spec:
>   hosts:
>     - httpbin.org
>   ports:
>     - number: 443
>       name: https
>       protocol: HTTPS
>   location: MESH_EXTERNAL
>   resolution: DNS
> ```
>
> Apply it:
>
> ```sh
> kubectl apply -f serviceentry-httpbin-org.yaml
> ```
>
> Then check the result:
>
> ```sh
> call_external https://httpbin.org/get
> call_external http://httpbin.org/get
> kubectl logs -n bookinfo deploy/curl -c istio-proxy --tail=2
> ```
>
> Expect `200`, then `000`, because only port `443` is listed. The log now names a real cluster for the HTTPS call: `outbound|443||httpbin.org`. One port allowed, everything else still refused. That pair of results is the whole point of `REGISTRY_ONLY` plus `ServiceEntry`: egress becomes a list of charted planets you maintain, rather than an assumption you inherit.

## Confirming registration

A registered external host gets a cluster in every proxy allowed to see it, exactly like an in-cluster Service. The new planet is now on every ship's star chart. This is the check that answers "is this host registered for this workload?" without sending traffic.

> [!TIP]
> **Try it — the external host in the proxy's cluster list**
>
> ```sh
> istioctl proxy-config cluster deploy/curl -n bookinfo | grep -iE 'httpbin.org|wikipedia' || echo "(no match)"
> ```
>
> Expect one line for `httpbin.org` on port `443`, direction `outbound`, with the type `STRICT_DNS`, and no line for Wikipedia yet. `STRICT_DNS` is Envoy's discovery type for `resolution: DNS` — the proxy resolves the name itself and refreshes it. Compare it with the `EDS` you saw for in-cluster Services in section 010: different mechanisms, same cluster abstraction.

## Wildcards

For a service whose hostnames you cannot list — a CDN, an object store with per-bucket names, every language edition of a website — a wildcard plus `resolution: NONE` is the shape. A wildcard is a pattern that matches many names, so `*.wikipedia.org` matches every subdomain: a whole star cluster charted with one entry.

```yaml
apiVersion: networking.istio.io/v1
kind: ServiceEntry
metadata:
  name: wikipedia
  namespace: bookinfo
spec:
  hosts:
    - "*.wikipedia.org"
  ports:
    - number: 443
      name: https
      protocol: HTTPS
  location: MESH_EXTERNAL
  resolution: NONE
```

`NONE` because DNS cannot look up a wildcard — which name should it look up? The proxy forwards to the address the application already resolved itself. This is broad — it permits every host under that suffix — so it is a deliberate trade of precision for practicality, not a default. (`protocol: TLS` works here too; with no TLS origination the proxy can only read the SNI name either way.)

> [!TIP]
> **Try it — a whole domain with one entry**
>
> Save this as `serviceentry-wikipedia.yaml`:
>
> ```yaml
> apiVersion: networking.istio.io/v1
> kind: ServiceEntry
> metadata:
>   name: wikipedia
>   namespace: bookinfo
> spec:
>   hosts:
>     - "*.wikipedia.org"
>   ports:
>     - number: 443
>       name: https
>       protocol: HTTPS
>   location: MESH_EXTERNAL
>   resolution: NONE
> ```
>
> Apply it:
>
> ```sh
> kubectl apply -f serviceentry-wikipedia.yaml
> ```
>
> Then check the result:
>
> ```sh
> call_external https://de.wikipedia.org/
> call_external https://en.wikipedia.org/wiki/Istio
> kubectl logs -n bookinfo deploy/curl -c istio-proxy --tail=1 | grep wikipedia
> ```
>
> Expect:
>
> ```text
> 301 ...
>   exit=0
> 404 ...
>   exit=0
> ... outbound|443||*.wikipedia.org ... de.wikipedia.org
> ```
>
> (Times trimmed.) Any HTTP status code means the connection got out — the code is Wikipedia's own answer, and `404` only means that page does not exist. The log names the wildcard cluster. Remove it again with `kubectl delete -f serviceentry-wikipedia.yaml`.

> *The declared `protocol` decides how much of Istio applies to an external host; `TCP` gets you a working connection and nothing else.*

## Common pitfalls

> [!WARNING]
> **Naming the port wrong.** `protocol` on a `ServiceEntry` port decides whether you get HTTP routing or an opaque byte stream, exactly as a Service port name does in section 010.
>
> **Choosing the wrong `resolution`.** `DNS` makes the proxy resolve the name itself; `STATIC` requires `endpoints`; `NONE` passes through to whatever address the caller used. They are not interchangeable.
>
> **Leaving `location` at the default when the host is in-mesh.** `MESH_EXTERNAL` and `MESH_INTERNAL` differ in whether mTLS and identity apply, which module 3 depends on.
>
> **Assuming a `ServiceEntry` is private to its namespace.** It is exported mesh-wide unless `exportTo` says otherwise.
>
> **Expecting a wildcard host to work like a DNS name.** A `*.example.com` entry cannot be resolved by the proxy, so it needs `resolution: NONE` or a gateway in front of it.
>
> **Registering HTTPS and calling plain HTTP.** A `ServiceEntry` with only port `443` does nothing for `http://` on port `80`. Every port the application uses must be listed.
