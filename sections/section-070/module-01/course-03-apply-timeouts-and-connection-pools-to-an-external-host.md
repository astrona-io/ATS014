# Apply Timeouts And Connection Pools To An External Host

A `ServiceEntry` is more than an allow-list. Once it adds a host to the service registry, that host behaves like any other host in the mesh. A `VirtualService` sets how requests to a host are routed, and a `DestinationRule` sets what happens after routing picks a host. Both work on an external host exactly as they work on a Service inside the cluster.

The commands below need two objects applied in your playground: the `REGISTRY_ONLY` `Sidecar` resource named `default` in `starfleet`, and the `httpbin-org` `ServiceEntry` with only port `443` declared as `HTTPS`.

## What you can apply to somebody else's API

These are the features you can put on an external host, and the object that carries each one:

| Object | What it can do to an external host |
| --- | --- |
| `VirtualService` | a timeout, retries, routing by path, fault injection to test your own error handling |
| `DestinationRule` | a connection pool, outlier detection, a load balancing policy |

None of this needs help from the external host. The sidecar proxy (Envoy) in your own client pod enforces all of it, on the way out. The timeout is the clearest and most useful example: a deadline on a third-party API that you do not control and cannot change.

## HTTP rules need an HTTP port

There is a catch. The `httpbin-org` `ServiceEntry` declares `httpbin.org` only on port `443` with `protocol: HTTPS`. On HTTPS the sidecar proxy sees only encrypted bytes. It cannot see where one request ends, so a timeout has nothing to measure. HTTP rules need a **plain HTTP port**. To see this, try a timeout on a port that is not in the registry yet.

If your terminal does not have the `call_external` helper yet, paste it first. It sends one request from the `shuttle` pod and prints the status code, the time and the exit code of `curl`:

<!-- astrona:playground:renew -->

```sh
call_external() { kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" --max-time 10 "$@"; echo "  exit=$?"; }
```

Save this as `virtualservice-httpbin-org-timeout.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: httpbin-org
  namespace: starfleet
spec:
  hosts:
  - httpbin.org
  http:
  - timeout: 2s
    route:
    - destination:
        host: httpbin.org
        port:
          number: 80
```

The route names port `80`, because an HTTP rule can only work on a plain HTTP port.

Apply it:

```sh
kubectl apply -f virtualservice-httpbin-org-timeout.yaml
```

Then call a path that waits 4 seconds before it responds, and run `istioctl analyze`, which checks Istio objects for mistakes:

```sh
call_external http://httpbin.org/delay/4
istioctl analyze -n starfleet
```

You should see:

```text
000 0.010438s
command terminated with exit code 56
  exit=56
Error [IST0101] (VirtualService starfleet/httpbin-org) Referenced host:port not found: "httpbin.org:80"
```

The `VirtualService` exists, but port `80` is not in the registry, so the sidecar proxy still refuses the request. `istioctl analyze` names the gap with `IST0101`: the host and port the route points at do not exist.

The fix is to add port `80` as `HTTP` next to port `443`. The object keeps the same name, so applying it replaces the HTTPS-only version. Save this as `serviceentry-httpbin-org-http-and-https.yaml`:

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
  - number: 80
    name: http
    protocol: HTTP
  - number: 443
    name: https
    protocol: HTTPS
  location: MESH_EXTERNAL
  resolution: DNS
```

Apply it:

```sh
kubectl apply -f serviceentry-httpbin-org-http-and-https.yaml
```

Then call the slow path and a fast one, and read the `shuttle` pod's access log, where the sidecar proxy writes one line per request:

```sh
call_external http://httpbin.org/delay/4
call_external http://httpbin.org/get
kubectl logs -n starfleet deploy/shuttle -c istio-proxy --tail=2
```

You should see (log lines shortened):

```text
504 2.015458s
  exit=0
200 0.278113s
  exit=0
[...] "GET /delay/4 HTTP/1.1" 504 UT response_timeout ... "httpbin.org" "52.21.224.34:80" outbound|80||httpbin.org ...
[...] "GET /get HTTP/1.1" 200 - via_upstream ... "httpbin.org" "32.194.118.12:80" outbound|80||httpbin.org ...
```

The slow call returned `504` after 2 seconds, not 4. The response flag `UT` (upstream timeout) shows that the sidecar proxy ended the request. The fast call still returned `200`. The access log now shows full HTTP lines with the method, the path and the host, because the proxy can read the request. You have set a deadline on an outside API from your own client pod.

If you want HTTP features **and** an encrypted connection, the sidecar proxy must add the encryption itself on the way out. That is called **TLS origination**: the application sends plain HTTP, and the proxy opens the TLS (Transport Layer Security) connection to the external host.

## How a refusal looks on an HTTP port

Port `80` now has an HTTP **listener** in the `shuttle` pod's sidecar proxy. A listener is the part of Envoy that accepts connections on one port. That changes how a refusal looks on port `80`, for every other host too. Read the route table for port `80`, then call a host that is not in the registry:

```sh
istioctl proxy-config routes deploy/shuttle -n starfleet --name 80
call_external http://www.google.com/
kubectl logs -n starfleet deploy/shuttle -c istio-proxy --tail=1
```

You should see (log line shortened):

```text
NAME     VHOST NAME         DOMAINS                       MATCH     VIRTUAL SERVICE
80       httpbin.org:80     httpbin.org, httpbin.org.     /*        httpbin-org.starfleet
80       block_all          *                             /*
502 0.021723s
  exit=0
[...] "GET / HTTP/1.1" 502 - direct_response ... "www.google.com" "-" - - 142.251.155.119:80 ... block_all
```

The route table on port `80` has two entries: `httpbin.org` with your `VirtualService`, and **`block_all`** for every other host name. `www.google.com` is not in the registry, so its request matches `block_all`, and the sidecar proxy answers `502` itself (`direct_response`). This is how plain HTTP is refused once a known host uses the same port: `502`, not `000`.

## A connection pool for an external host

A `DestinationRule` works the same way on an external host, and in production it is often worth even more. A connection pool on an outside dependency stops one slow partner API from using up every worker in your application. Requests over the limit fail at once with `503` and the `UO` flag; Envoy calls these limits circuit breakers.

To see it, allow only one connection and one waiting request. Save this as `destinationrule-httpbin-org.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: httpbin-org
  namespace: starfleet
spec:
  host: httpbin.org
  trafficPolicy:
    connectionPool:
      tcp:
        maxConnections: 1
      http:
        http1MaxPendingRequests: 1
```

Apply it:

```sh
kubectl apply -f destinationrule-httpbin-org.yaml
```

Then look at the limits in the `shuttle` pod's sidecar proxy, and send 6 slow requests at the same time:

```sh
istioctl proxy-config cluster deploy/shuttle -n starfleet --fqdn httpbin.org --port 80 -o json | grep -A6 circuitBreakers
kubectl exec -n starfleet deploy/shuttle -- sh -c \
  'for i in 1 2 3 4 5 6; do curl -s -o /dev/null -w "%{http_code}\n" http://httpbin.org/delay/1 & done; wait' | sort | uniq -c
kubectl logs -n starfleet deploy/shuttle -c istio-proxy --tail=6 | grep ' 503 ' | tail -1
```

You should see (log line shortened):

```text
        "circuitBreakers": {
            "thresholds": [
                {
                    "maxConnections": 1,
                    "maxPendingRequests": 1,
                    "maxRequests": 4294967295,
   2 200
   4 503
[...] "GET /delay/1 HTTP/1.1" 503 UO upstream_reset_before_response_started{overflow} ... outbound|80||httpbin.org ...
```

The limits from your `DestinationRule` sit in the sidecar proxy as Envoy circuit breaker thresholds. One request used the connection, one waited, and the proxy turned the other four away at once with `503` and the flag `UO` (upstream overflow). The proxy treats the external host like any other destination.

## `exportTo`: which namespaces may use a `ServiceEntry`

A `ServiceEntry` lives in a namespace, but by **default it is exported to the whole mesh**: sidecar proxies in every namespace may use it. That surprises people, and it matters. Under `REGISTRY_ONLY`, a `ServiceEntry` that one team creates in its own namespace opens that host for every namespace in the mesh. The `exportTo` field narrows it:

```yaml
spec:
  exportTo:
  - "."
```

The values are `.` for the object's own namespace, `*` for every namespace (the default), or a list of namespace names. In a mesh where the point is control, put `exportTo: ["."]` on every `ServiceEntry`. Otherwise one namespace's allow-list silently becomes everyone's.

You can now put a timeout and a connection pool on an external host, and you know that both need the port declared as `HTTP`. You also know that a plain HTTP refusal turns into `502` with `block_all` once a known host shares the port, and that `exportTo` controls which namespaces may use an entry. The open question is what happens when an entry exists and is correct, but a caller still cannot use it.

## Common pitfalls

> [!WARNING]
> - **Expecting HTTP features on an HTTPS or TCP port.** No timeouts, no retries, no path routing. The declared `protocol` is what turns HTTP handling on.
> - **Leaving the port out of a route when the host has several ports.** `istioctl analyze` reports `IST0112`. Name the port in `destination.port.number`.
> - **Reading `502` as a broken partner API.** With `block_all` in the access log, the sidecar proxy refused the host because it is not in the registry.
> - **Assuming a `ServiceEntry` is private to its namespace.** It is exported to every namespace unless `exportTo` says otherwise.

## Your mission: Allow One External Host Under REGISTRY_ONLY Lab

You can now add an external host to the registry, give its port the right protocol, and put a timeout on it. The lab asks you to open exactly one outside endpoint in a mesh that refuses everything, keep a second endpoint blocked, and give the open one a 2 second timeout. The lab uses a different small app: a `tester` client in the `egress-demo` namespace and two pods in `outside-mesh`, on a mesh that has `REGISTRY_ONLY` set for the whole mesh.

The lab runs in its own cluster, so first pause your playground. Nothing in it is lost:

```sh
astrona stop ats-014-playground-070-01
```

Then start the lab:

```sh
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-070/module-01/labs/lab-01
```

The task is on the next page. Solve it on your own first. When you think you are done, send it for grading:

```sh
astrona submit -c sections/section-070/module-01/labs/lab-01
```

When the lab is done, remove it and start your playground again:

```sh
astrona destroy ats-014-lab-070-01
astrona start ats-014-playground-070-01
```
