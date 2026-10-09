# Add An External Host With ServiceEntry

Under `REGISTRY_ONLY`, the sidecar proxy refuses every host that is not in the service registry. The service registry is the list of hosts and endpoints that `istiod`, Istio's control plane, knows about. A **`ServiceEntry`** adds a host outside the mesh to that list. It has four fields that matter, and each field answers one question. One of them, the port's `protocol`, decides how much of Istio you can use on that host later.

The commands below need the `REGISTRY_ONLY` `Sidecar` resource named `default` in the `starfleet` namespace applied in your playground. That `Sidecar` makes the sidecar proxies in `starfleet` refuse every host outside the registry.

## The four fields

Take `httpbin.org`, a public test API, as the example. A `ServiceEntry` for it needs four answers, one per field under `spec`:

| Field | Answers | Value for `httpbin.org` |
| --- | --- | --- |
| `hosts` | What is the host called? | `httpbin.org` |
| `ports` | On which port, with which protocol? | `443`, named `https`, protocol `HTTPS` |
| `location` | Is it part of the mesh, or somebody else's service? | `MESH_EXTERNAL` |
| `resolution` | How does the proxy find an address for it? | `DNS` |

The sections below explain each field in turn, starting with the name.

### `hosts`

The `hosts` field lists the names this entry covers. A wildcard such as `*.example.com` covers every name under that domain. You use a wildcard for a service whose host names you cannot list.

With `resolution: DNS`, the **sidecar proxy** looks the name up from inside the pod, with the cluster's DNS (the Domain Name System, which turns host names into addresses). A name that only resolves on your laptop does not work.

### `ports`, and why `protocol` matters most

Each port has a number, a name and a **protocol**. The protocol tells the sidecar proxy what kind of traffic to expect on that port. That decides how much of Istio applies:

| `protocol` | The proxy will |
| --- | --- |
| `HTTP` | read every request, so `VirtualService` rules, timeouts, retries and path routing all work |
| `HTTPS` | pass an encrypted stream through, reading only the host name in the TLS (Transport Layer Security) handshake, called SNI (Server Name Indication) |
| `TLS` | the same: read only the SNI |
| `TCP` | move bytes, with no idea what they contain |

Declaring `TCP` when the traffic is HTTP is not an error. The connection works, but with none of the features you probably wanted. The symptom is a `VirtualService` on that host that does nothing at all. Keep the port `name` in line with the `protocol` too: a port named `http` and declared `TCP` only confuses the next reader.

### `location`: `MESH_EXTERNAL` or `MESH_INTERNAL`

The `location` field says whether the endpoints belong to the mesh:

| Value | Means | Use for |
| --- | --- | --- |
| `MESH_EXTERNAL` | not part of the mesh | a third party's API |
| `MESH_INTERNAL` | part of the mesh, just not in Kubernetes | a virtual machine you run with a sidecar proxy |

The difference is real. `MESH_INTERNAL` tells Istio the endpoints are mesh members, so mTLS (mutual TLS, where both sides present a certificate) and workload identity apply. `MESH_EXTERNAL` gives you routing and policy, but no identity. That is correct for somebody else's API, because it does not take part in Istio's mTLS. `MESH_EXTERNAL` is the default.

### `resolution`: how the proxy finds an address

The `resolution` field tells the sidecar proxy where the endpoint addresses come from:

| Value | The proxy | Use with |
| --- | --- | --- |
| `DNS` | looks the host name up itself, and keeps the answer fresh | a public host name |
| `STATIC` | uses the addresses listed under `endpoints` | fixed IP addresses |
| `NONE` | forwards to the address the application already chose | a wildcard host |
| `DNS_ROUND_ROBIN` | looks the name up and uses one address at a time | an endpoint behind a load balancer |

`DNS` is right for nearly every public API. `NONE` is what a wildcard needs, because there is no single name to look up.

## Add `httpbin.org` for HTTPS only

Now add a real host to the registry, with the four answers from the table above: its name, port `443` with `HTTPS`, somebody else's service (`MESH_EXTERNAL`), and found by `DNS`.

If your terminal does not have the `call_external` helper yet, paste it first. It sends one request from the `shuttle` pod and prints the status code, the time and the exit code of `curl`:

<!-- astrona:playground:renew -->

```sh
call_external() { kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" --max-time 10 "$@"; echo "  exit=$?"; }
```

Save this as `serviceentry-httpbin-org.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: ServiceEntry
metadata:
  name: httpbin-org
  namespace: starfleet
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

Apply it:

```sh
kubectl apply -f serviceentry-httpbin-org.yaml
```

Then call the host over HTTPS and over plain HTTP, and read the `shuttle` pod's access log, where the sidecar proxy writes one line per request or connection:

```sh
call_external https://httpbin.org/get
call_external http://httpbin.org/get
kubectl logs -n starfleet deploy/shuttle -c istio-proxy --tail=2
```

You should see (log lines shortened):

```text
200 0.502151s
  exit=0
000 0.005651s
command terminated with exit code 56
  exit=56
[...] "- - -" 0 UH - - "-" 0 0 0 - "-" "-" "-" "-" "-" BlackHoleCluster - 100.56.179.159:80 ...
[...] "- - -" 0 - - - "-" 901 4875 617 - "-" "-" "-" "-" "34.227.237.26:443" outbound|443||httpbin.org ... httpbin.org -
```

HTTPS gets `200`, and the access log now names a real Envoy cluster, `outbound|443||httpbin.org`. A cluster is Envoy's name for a destination and its endpoints. Plain HTTP is still refused with `BlackHoleCluster`, because only port `443` is in the registry. The two lines can appear in either order, because the proxy writes the line for a TCP connection when the connection closes.

One port allowed, everything else still refused. That pair of results is the point of `REGISTRY_ONLY` plus `ServiceEntry`: outbound traffic becomes a list of hosts that you keep, not something you inherit.

## Confirm the host is in the proxy's configuration

A host from a `ServiceEntry` gets a cluster in every sidecar proxy that may see it, exactly like a Service inside the cluster. You can check that without sending a request. `istioctl proxy-config cluster` lists the clusters one proxy holds, and `istioctl proxy-config endpoints` lists the addresses behind one cluster:

```sh
istioctl proxy-config cluster deploy/shuttle -n starfleet | grep -iE 'httpbin.org|wikipedia' || echo "(no match)"
istioctl proxy-config endpoints deploy/shuttle -n starfleet --cluster "outbound|443||httpbin.org"
```

You should see (endpoint list shortened):

```text
httpbin.org                               443       -          outbound      STRICT_DNS
ENDPOINT               STATUS      OUTLIER CHECK     CLUSTER
100.56.179.159:443     HEALTHY     OK                outbound|443||httpbin.org
18.233.182.23:443      HEALTHY     OK                outbound|443||httpbin.org
3.225.83.162:443       HEALTHY     OK                outbound|443||httpbin.org
...
```

There is one line for `httpbin.org` on port `443`, and no line for Wikipedia yet. The type `STRICT_DNS` is how Envoy shows `resolution: DNS`: the proxy looks the name up itself, and every address it gets back becomes an endpoint.

## Wildcard hosts

Some services have host names you cannot list: a content delivery network, an object store with a name per bucket, or every language edition of a website. For these you use a wildcard host with `resolution: NONE`. `*.wikipedia.org` matches every name under `wikipedia.org` with one entry.

It has to be `NONE`, because DNS cannot look up a wildcard: there is no single name to ask for. The sidecar proxy forwards the request to the address the application already looked up itself. This is broad, because it allows every host under that domain, so use it on purpose and not by default.

First, check that Wikipedia is refused:

```sh
call_external https://de.wikipedia.org/
```

```text
000 0.101233s
command terminated with exit code 35
  exit=35
```

Save this as `serviceentry-wikipedia.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: ServiceEntry
metadata:
  name: wikipedia
  namespace: starfleet
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

Apply it:

```sh
kubectl apply -f serviceentry-wikipedia.yaml
```

Then call two different Wikipedia hosts, and read the access log:

```sh
call_external https://de.wikipedia.org/
call_external https://en.wikipedia.org/wiki/Istio
kubectl logs -n starfleet deploy/shuttle -c istio-proxy --tail=2
```

You should see (log lines shortened):

```text
301 0.095577s
  exit=0
404 0.819689s
  exit=0
[...] "185.15.59.224:443" outbound|443||*.wikipedia.org ... de.wikipedia.org -
[...] "185.15.59.224:443" outbound|443||*.wikipedia.org ... en.wikipedia.org -
```

Any HTTP status code means the connection got out: `301` and `404` are Wikipedia's own responses, not the mesh's. Both hosts went through one cluster, `outbound|443||*.wikipedia.org`, and the access log shows the real host name the proxy read from the SNI in the TLS handshake.

Remove the wildcard entry, so Wikipedia is refused again:

```sh
kubectl delete -f serviceentry-wikipedia.yaml
```

You can now write a `ServiceEntry` with the four answers it needs, check that a sidecar proxy received it, and open a whole domain with a wildcard. The `httpbin-org` entry stays applied, for HTTPS only. The open question is what else you can do with an external host once it is in the registry, and why the HTTPS-only port limits that.

## Common pitfalls

> [!WARNING]
> - **Declaring the wrong protocol.** `protocol` on a `ServiceEntry` port decides whether you get HTTP features or an opaque byte stream. `TCP` gives a working connection and nothing else.
> - **Choosing the wrong `resolution`.** `DNS` makes the proxy look the name up; `STATIC` needs `endpoints`; `NONE` forwards to whatever address the caller used. They are not interchangeable.
> - **Using `MESH_EXTERNAL` for a workload that is part of the mesh.** `MESH_EXTERNAL` and `MESH_INTERNAL` differ in whether mTLS and identity apply.
> - **Using `resolution: DNS` with a wildcard host.** There is no single name to look up. Use `NONE`.
> - **Adding HTTPS and calling plain HTTP.** A `ServiceEntry` with only port `443` does nothing for `http://` on port `80`. List every port the application uses.
> - **Forgetting who looks the name up.** With `resolution: DNS`, the host name must resolve from inside the pod, not from your machine.
