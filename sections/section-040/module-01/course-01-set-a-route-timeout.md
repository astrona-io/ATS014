# Set A Route Timeout

When a service stops answering, the client that called it waits with the connection open. The clients of that client wait too. One slow backend can stall a whole chain of calls, and nothing crashes. A **timeout** fixes this: it is the longest time a client waits for a response before it gives up and returns an error.

In Istio, a timeout is one field on a rule of a `VirtualService`. A `VirtualService` is the Istio object that sets how requests to a host are routed: match rules, read from top to bottom, and the destinations, timeouts and retries for each rule. This part shows that there is no timeout until you set one, how to set it, and how to read the access log to see that it fired.

## No timeout by default

Istio sets **no** HTTP timeout unless you write one. A request to a backend that takes 3 seconds to answer simply takes 3 seconds. A request to a backend that never answers keeps waiting.

You can see this from the `shuttle` pod, the test client in the `starfleet` namespace. Paste this helper into your terminal first. It sends one request from `shuttle` with `curl` and prints the status code and the total time:

<!-- astrona:playground:renew -->

```sh
status_and_time() { kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" "$@"; }
```

The `probe` Service is an HTTP echo server on port 8000. Its `/delay/3` path waits 3 seconds before it answers. Send one request to it:

```sh
status_and_time http://probe:8000/delay/3
```

You should see:

```text
200 3.023506s
```

Nothing stopped the slow request. In a real system, those 3 seconds are 3 seconds of an open connection in every service between the user and this backend. If the backend hangs for good, every caller hangs with it.

## The `timeout` field

The fix is the `timeout` field. It sits on a rule of a `VirtualService`, next to `route`. Its value is a duration such as `500ms`, `0.5s`, `2s` or `1m`. Three facts decide how it behaves:

- **The client's sidecar proxy measures it.** A sidecar proxy is the Envoy container that Istio adds to each pod; all traffic in and out of the pod passes through it. The timeout lives in the sidecar proxy of the pod that **sends** the request, not on the receiver. So it protects the client even when the receiver never answers at all.
- **The client gets a `504`.** When the time runs out, the client's own sidecar proxy cancels the request and returns `504 Gateway Timeout` by itself. The receiver never answered.
- **It belongs to one rule.** One `VirtualService` can give different paths different timeouts: a long one for a slow report page, a short one for everything else.

Now give every request to the probe a 1-second timeout. Save this as `virtualservice-probe-timeout.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: probe
  namespace: starfleet
spec:
  hosts:
  - probe
  http:
  - route:
    - destination:
        host: probe
    timeout: 1s
```

Apply it:

```sh
kubectl apply -f virtualservice-probe-timeout.yaml
```

Then check the result. Send a slow request and a fast one:

```sh
status_and_time http://probe:8000/delay/3
status_and_time http://probe:8000/delay/0
```

You should see:

```text
504 1.005886s
200 0.006127s
```

The slow request stops after 1 second. The fast one is not affected. The time shown is the timeout, not the delay. That is how you tell a timeout that fired from a slow request that succeeded.

## Read the timeout in the access log

The status code tells you *that* a request failed. The access log tells you *which proxy* failed it. In this playground, access logs are switched on, so every sidecar proxy writes one line per request. When something goes wrong, the line carries a short code called the **response flag**.

The flag for a timeout that fired is **`UT`**, short for "upstream timeout". "Upstream" is the word Envoy uses for the service being called. Read the `shuttle` sidecar proxy's access log line for the slow request:

```sh
kubectl logs -n starfleet deploy/shuttle -c istio-proxy --tail=3 | grep 'delay/3'
```

You should see a line like this one (shortened):

```text
[2026-10-08T20:51:53.596Z] "GET /delay/3 HTTP/1.1" 504 UT response_timeout ... 1001 ... "probe:8000" ...
```

`504 UT` means the `shuttle` pod's own sidecar proxy created the `504`, because the timeout ran out. `1001` is how long the request took in milliseconds. A `504` **without** `UT` came from somewhere further along the path. Knowing this stops you from debugging the wrong service.

> [!TIP]
> Before you debug a `504`, read the response flag. `UT` means "my own timeout fired": look at the timeout on the client's `VirtualService`, not at the receiver.

These flags come up again and again when requests fail. Keep this short list nearby:

| Flag | Meaning |
| --- | --- |
| `UT` | upstream timeout: a route timeout fired |
| `DI` | delay injected: fault injection added a delay |
| `URX` | upstream retry limit exceeded: all retries are used up |
| `UO` | upstream overflow: a connection pool limit was reached, so the proxy rejected the request |
| `UH` | no healthy upstream: there is no healthy endpoint to send to |
| `UF` | upstream connection failure: the connection could not be made |

You now know that Istio sets no route timeout by default, how to add one with the `timeout` field, and how to prove it fired with `504` and the `UT` flag. The open question is how to test a timeout on a real call chain, where one service calls another. That needs a backend that is slow on purpose.

## Common pitfalls

> [!WARNING]
> - **Assuming there is a default.** There is no route timeout unless you write one.
> - **Reading a `504` as coming from the receiver.** A timeout `504` is created by the client's own sidecar proxy. The `UT` flag tells them apart.
> - **Confusing it with a connection timeout.** `timeout` limits the whole exchange, connecting included. The time to make the connection is a separate setting on a `DestinationRule`: `connectionPool.tcp.connectTimeout`.
> - **Forgetting the application's own timeout.** An application can have its own limit. If it is shorter than Istio's, the application gives up first.
