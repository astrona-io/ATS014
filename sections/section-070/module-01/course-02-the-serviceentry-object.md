# The `ServiceEntry` Object

Astronaut, a `ServiceEntry` adds a planet from another solar system to the star chart. It has four fields that matter, and each one answers one question. One of them, the port's `protocol`, decides how much of Istio you can use on that planet later.

The commands below need the `REGISTRY_ONLY` `Sidecar` applied in your playground, and the `call_external` helper pasted into your terminal.

## The object

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

| Field | Answers |
| --- | --- |
| `hosts` | What is it called? |
| `ports` | On which port, speaking which protocol? |
| `location` | Is it part of the mesh, or somebody else's? |
| `resolution` | How does the proxy find an address for it? |

## `hosts`

The names this entry covers. A wildcard such as `*.example.com` covers every name under that domain, which is how you chart a service whose host names you cannot list.

With `resolution: DNS`, the **proxy** looks the name up, from inside the pod, with the cluster's DNS (the Domain Name System, which turns host names into addresses). A name that only resolves on your laptop does not work.

## `ports`, and why `protocol` is the important word

Each port has a number (think of it as a radio channel), a name, and a **protocol**. The protocol tells the communications officer which language the signals on that channel speak. That decides how much of Istio applies:

| `protocol` | The proxy will |
| --- | --- |
| `HTTP` | read every request, so `VirtualService` rules, timeouts, retries and path routing all work |
| `HTTPS` | pass an encrypted stream through, reading only the host name in the TLS (Transport Layer Security) handshake, called SNI (Server Name Indication) |
| `TLS` | the same: read only the SNI |
| `TCP` | move bytes, with no idea what they say |

Declaring `TCP` when the traffic is HTTP is not an error. The connection works, with none of the features you probably wanted. The symptom is a `VirtualService` on that host that does nothing at all. Keep the port `name` in line with the `protocol` too: a port named `http` and declared `TCP` only confuses the next reader.

## `location`: `MESH_EXTERNAL` or `MESH_INTERNAL`

| Value | Means | Use for |
| --- | --- | --- |
| `MESH_EXTERNAL` | not part of the mesh | a third party's API |
| `MESH_INTERNAL` | part of the mesh, just not in Kubernetes | a virtual machine you run with a sidecar |

The difference is real. `MESH_INTERNAL` tells Istio the endpoints are mesh members, so mutual TLS (mTLS, the secret handshake both ships check before they talk) and workload identity apply. `MESH_EXTERNAL` gives you routing and policy, but no identity. That is correct for somebody else's API: a planet in another solar system does not know Istio's handshake. `MESH_EXTERNAL` is the default.

## `resolution`: how an address is found

| Value | The proxy | Use with |
| --- | --- | --- |
| `DNS` | looks the host name up itself, and keeps the answer fresh | a public host name |
| `STATIC` | uses the addresses listed under `endpoints` | fixed IP addresses |
| `NONE` | forwards to the address the application already chose | a wildcard host |
| `DNS_ROUND_ROBIN` | looks the name up and uses one address at a time | an endpoint behind a load balancer |

`DNS` is right for nearly every public API. `NONE` is what a wildcard needs, because there is no single name to look up.

## Chart your first planet

Time to put a real planet on the chart. `httpbin.org` is a public test API, so the four answers are simple: its name, port `443` speaking `HTTPS`, somebody else's (`MESH_EXTERNAL`), and found by `DNS`.

<!-- astrona:playground:renew -->

### Chart `httpbin.org` for HTTPS only

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

Then call the planet over HTTPS and over plain HTTP, and read the flight log:

```sh
call_external https://httpbin.org/get
call_external http://httpbin.org/get
kubectl logs -n starfleet deploy/shuttle -c istio-proxy --tail=2
```

You should see (log lines trimmed):

```text
200 0.502151s
  exit=0
000 0.005651s
command terminated with exit code 56
  exit=56
[...] "- - -" 0 UH - - "-" 0 0 0 - "-" "-" "-" "-" "-" BlackHoleCluster - 100.56.179.159:80 ...
[...] "- - -" 0 - - - "-" 901 4875 617 - "-" "-" "-" "-" "34.227.237.26:443" outbound|443||httpbin.org ... httpbin.org -
```

HTTPS gets `200`, and the flight log now names a real cluster, `outbound|443||httpbin.org`. Plain HTTP still falls into the black hole, because only port `443` is on the chart. The two lines can appear in either order: the proxy writes a line for a TCP connection when it closes.

One port allowed, everything else still refused. That pair of results is the whole point of `REGISTRY_ONLY` plus `ServiceEntry`: egress becomes a list of charted planets that you keep, not something you inherit.

## Confirm the planet is on the chart

A charted external host gets a cluster in every proxy that may see it, exactly like a Service inside the cluster. You can check that without sending a signal.

### Find the planet in the shuttle's proxy

```sh
istioctl proxy-config cluster deploy/shuttle -n starfleet | grep -iE 'httpbin.org|wikipedia' || echo "(no match)"
istioctl proxy-config endpoints deploy/shuttle -n starfleet --cluster "outbound|443||httpbin.org"
```

You should see (endpoint list trimmed):

```text
httpbin.org                               443       -          outbound      STRICT_DNS
ENDPOINT               STATUS      OUTLIER CHECK     CLUSTER
100.56.179.159:443     HEALTHY     OK                outbound|443||httpbin.org
18.233.182.23:443      HEALTHY     OK                outbound|443||httpbin.org
3.225.83.162:443       HEALTHY     OK                outbound|443||httpbin.org
...
```

One line for `httpbin.org` on port `443`, and no line for Wikipedia yet. The type `STRICT_DNS` is how Envoy shows `resolution: DNS`: the proxy looks the name up itself, and every address it got back becomes an endpoint.

## Wildcards

For a service whose host names you cannot list, such as a content delivery network, an object store with a name per bucket, or every language edition of a website, use a wildcard host with `resolution: NONE`. `*.wikipedia.org` matches every name under `wikipedia.org`: a whole star cluster charted with one entry.

It is `NONE` because DNS cannot look up a wildcard: which name should it look up? The proxy forwards the signal to the address the application already looked up itself. This is broad, because it allows every host under that domain. Use it on purpose, not by default.

### Chart a whole domain with one entry

First, see that Wikipedia is refused:

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

Then call two different Wikipedia hosts, and read the flight log:

```sh
call_external https://de.wikipedia.org/
call_external https://en.wikipedia.org/wiki/Istio
kubectl logs -n starfleet deploy/shuttle -c istio-proxy --tail=2
```

You should see (log lines trimmed):

```text
301 0.095577s
  exit=0
404 0.819689s
  exit=0
[...] "185.15.59.224:443" outbound|443||*.wikipedia.org ... de.wikipedia.org -
[...] "185.15.59.224:443" outbound|443||*.wikipedia.org ... en.wikipedia.org -
```

Any HTTP status code means the connection got out: `301` and `404` are Wikipedia's own answers, not the mesh's. Both hosts went through one cluster, `outbound|443||*.wikipedia.org`, and the flight log shows the real host name the proxy read from the TLS handshake.

Remove the wildcard, so Wikipedia is closed again:

```sh
kubectl delete -f serviceentry-wikipedia.yaml
```

## Common pitfalls

> [!WARNING]
> - **Declaring the wrong protocol.** `protocol` on a `ServiceEntry` port decides whether you get HTTP features or a sealed byte stream. `TCP` gives a working connection and nothing else.
> - **Choosing the wrong `resolution`.** `DNS` makes the proxy look the name up; `STATIC` needs `endpoints`; `NONE` forwards to whatever address the caller used. They are not interchangeable.
> - **Using `MESH_EXTERNAL` for a workload that is part of the mesh.** `MESH_EXTERNAL` and `MESH_INTERNAL` differ in whether mutual TLS and identity apply.
> - **Using `resolution: DNS` with a wildcard host.** There is no single name to look up. Use `NONE`.
> - **Charting HTTPS and calling plain HTTP.** A `ServiceEntry` with only port `443` does nothing for `http://` on port `80`. List every port the application uses.
> - **Forgetting who looks the name up.** With `resolution: DNS`, the host name must resolve from inside the pod, not from your machine.

> *A `ServiceEntry` charts a planet with four answers: its name, its ports and their protocol, whose it is, and how to find its address.*
