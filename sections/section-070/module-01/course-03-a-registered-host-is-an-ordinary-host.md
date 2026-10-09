# A Registered Host Is An Ordinary Host

Astronaut, a `ServiceEntry` is more than an allow-list. Once a planet is on the star chart, it behaves like any other host in the mesh. The flight plan (`VirtualService`) and the docking instructions (`DestinationRule`) work on it exactly as they work on a Service inside the cluster.

The commands below need the `REGISTRY_ONLY` `Sidecar` and the `httpbin-org` `ServiceEntry` (HTTPS only) applied in your playground, and the `call_external` helper pasted into your terminal.

## What you can now do to somebody else's API

| Object | What it can do to an external host |
| --- | --- |
| `VirtualService` | a timeout, retries, routing by path, fault injection to test your own error handling |
| `DestinationRule` | a connection pool, outlier detection, a load balancing policy |

None of this needs help from the other solar system. Your own ship's communications officer enforces all of it, on the way out.

The timeout is the clearest example, and the most useful: a deadline on a third-party API you do not control and cannot change.

## HTTP rules need an HTTP port

There is a catch. The `ServiceEntry` you have charts `httpbin.org` only on port `443` with `protocol: HTTPS`. On HTTPS the proxy only sees sealed, encrypted bytes. It cannot see where one request ends, so a timeout has nothing to measure. HTTP rules need a **plain HTTP port**.

<!-- astrona:playground:renew -->

### Put a timeout on an HTTPS-only planet

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

The route names port `80`, because the plain HTTP port is the one an HTTP rule can work on.

Apply it:

```sh
kubectl apply -f virtualservice-httpbin-org-timeout.yaml
```

Then call a path that waits 4 seconds before it answers, and ask `istioctl analyze`:

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

The flight plan exists, but port `80` is not on the chart, so the signal still falls into the black hole. `istioctl analyze` names the gap: `IST0101`, the host and port the route points at do not exist.

### Add the plain HTTP port

Chart port `80` as `HTTP` next to port `443`. The object has the same name as before, so applying it replaces the HTTPS-only version. Save this as `serviceentry-httpbin-org-http-and-https.yaml`:

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

Then call the slow path and a fast one, and read the flight log:

```sh
call_external http://httpbin.org/delay/4
call_external http://httpbin.org/get
kubectl logs -n starfleet deploy/shuttle -c istio-proxy --tail=2
```

You should see (log lines trimmed):

```text
504 2.015458s
  exit=0
200 0.278113s
  exit=0
[...] "GET /delay/4 HTTP/1.1" 504 UT response_timeout ... "httpbin.org" "52.21.224.34:80" outbound|80||httpbin.org ...
[...] "GET /get HTTP/1.1" 200 - via_upstream ... "httpbin.org" "32.194.118.12:80" outbound|80||httpbin.org ...
```

`504` after 2 seconds, not 4. The flag `UT` (upstream timeout) shows that the proxy cut the signal off. The fast call still answers `200`. Now the flight log shows full HTTP lines, with the method, the path and the host, because the proxy can read the signal. A deadline on a planet in another solar system, set from your own ship.

If you want HTTP features **and** an encrypted connection, the proxy must add the encryption itself on the way out. That is called **TLS origination** (TLS, Transport Layer Security, is the encryption under HTTPS).

## The `502` signature

Port `80` now has an HTTP listener in the shuttle's proxy. That changes how a refusal looks on port `80`, for every other planet too.

### Read the route table on port 80

```sh
istioctl proxy-config routes deploy/shuttle -n starfleet --name 80
call_external http://www.google.com/
kubectl logs -n starfleet deploy/shuttle -c istio-proxy --tail=1
```

You should see (log line trimmed):

```text
NAME     VHOST NAME         DOMAINS                       MATCH     VIRTUAL SERVICE
80       httpbin.org:80     httpbin.org, httpbin.org.     /*        httpbin-org.starfleet
80       block_all          *                             /*
502 0.021723s
  exit=0
[...] "GET / HTTP/1.1" 502 - direct_response ... "www.google.com" "-" - - 142.251.155.119:80 ... block_all
```

The route table on port `80` has two entries: `httpbin.org` with your flight plan, and **`block_all`** for every other name. `www.google.com` is not on the chart, so its signal hits `block_all`, and the proxy answers `502` itself (`direct_response`). This is the plain HTTP refusal, astronaut: `502`, not `000`, as soon as a charted host shares the port.

## Docking instructions for an external host

A `DestinationRule` works the same way, and in production it is often worth even more. A connection pool on an outside dependency stops one slow partner API from tying up every worker in your application.

### Put a connection pool on `httpbin.org`

Allow only one connection and one waiting request. Save this as `destinationrule-httpbin-org.yaml`:

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

Then look at the limits in the shuttle's proxy, and send 6 slow signals at the same time:

```sh
istioctl proxy-config cluster deploy/shuttle -n starfleet --fqdn httpbin.org --port 80 -o json | grep -A6 circuitBreakers
kubectl exec -n starfleet deploy/shuttle -- sh -c \
  'for i in 1 2 3 4 5 6; do curl -s -o /dev/null -w "%{http_code}\n" http://httpbin.org/delay/1 & done; wait' | sort | uniq -c
kubectl logs -n starfleet deploy/shuttle -c istio-proxy --tail=6 | grep ' 503 ' | tail -1
```

You should see (log line trimmed):

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

The limits from your `DestinationRule` sit in the proxy as Envoy circuit breaker thresholds. One signal used the connection, one waited, and the other four were turned away at once with `503` and the flag `UO` (upstream overflow). The proxy does not know or care that the destination is outside the cluster.

## `exportTo`: who else may use your chart entry

A `ServiceEntry` lives in a namespace, but by **default it is exported to the whole mesh**. Every namespace may use it.

That surprises people, and it matters. Under `REGISTRY_ONLY`, a `ServiceEntry` that one team creates on its planet opens that host for every planet in the mesh. `exportTo` narrows it:

```yaml
spec:
  exportTo:
  - "."
```

The values are `.` for the object's own namespace, `*` for every namespace (the default), or a list of namespace names. In a mesh where the point is control, put `exportTo: ["."]` on every `ServiceEntry`. Otherwise one planet's allow-list silently becomes everyone's.

## Common pitfalls

> [!WARNING]
> - **Expecting HTTP features on an HTTPS or TCP port.** No timeouts, no retries, no path routing. The declared `protocol` is what turns HTTP handling on.
> - **Leaving the port out of a route when the host has several ports.** `istioctl analyze` reports `IST0112`. Name the port in `destination.port.number`.
> - **Reading `502` as a broken partner API.** With `block_all` in the flight log, the mesh refused the host. It is not on the chart.
> - **Assuming a `ServiceEntry` is private to its namespace.** It is exported to every namespace unless `exportTo` says otherwise.

> *A charted external host is an ordinary mesh host: timeouts, retries and connection pools apply to it unchanged, as long as its port speaks HTTP.*

## Your mission: Open Exactly One Route Out

You can now chart a planet, give its port the right protocol, and put a timeout on it. Now prove it in a graded mission: in a mesh that refuses everything, open exactly one route to an outside endpoint, keep a second one blocked, and give the open route a deadline.

The mission runs in its own training solar system, so first pause your playground. Nothing in it is lost:

```sh
astrona stop ats-014-playground-070-01
```

Then start the mission:

```sh
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-070/module-01/labs/lab-01
```

Read the task in [`question.md`](./labs/lab-01/question.md) and solve it on your own first. When you think you are done, send it for grading:

```sh
astrona submit -c sections/section-070/module-01/labs/lab-01
```

When the mission is done, remove it and wake your playground up again:

```sh
astrona destroy ats-014-lab-070-01
astrona start ats-014-playground-070-01
```
