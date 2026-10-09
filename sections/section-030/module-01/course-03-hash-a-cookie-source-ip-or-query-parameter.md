# Hash A Cookie, The Source IP Or A Query Parameter

Hashing a request header only works when the client adds that header. A browser usually cannot. This part shows the three other values that `consistentHash` can hash: a cookie, which Istio can even create itself, the client's IP address, and a query parameter. Each one fits a different kind of traffic, and each one has its own trap.

`consistentHash` is a form of `trafficPolicy.loadBalancer` in a `DestinationRule`, the Istio object that holds policies for traffic to one host. It makes the **sidecar proxy** (the Envoy proxy container that Istio adds to each pod) of the sending pod calculate a hash from a value in the request. The same value always gives the same hash, so it always reaches the same pod. A request that does not carry the value is spread over the pods as usual.

## Sticky by cookie

A **cookie** is a small named value that a server asks the browser to store, with the `Set-Cookie` response header. The browser then sends it back in the `Cookie` request header on every visit. For browser traffic, a cookie is usually the best value to hash. The `httpCookie` field takes a `name` and an optional `ttl` (time to live).

The important detail is `ttl`. **Setting `ttl` makes the sidecar proxy create the cookie** when a request arrives without one. The proxy adds a `Set-Cookie` header to the response, and the browser sends the cookie back from then on. That closes the "nothing to hash" gap for a first-time visitor. `ttl` is also how long the cookie stays valid.

If you leave `ttl` out, Istio only hashes a cookie the client already has. That is the right choice when another part of your system owns the session cookie.

<!-- astrona:playground:renew -->

### Let the sidecar proxy create a cookie

First paste this helper into your terminal. The `count_pods` function sends 8 requests from the `shuttle` pod to the `probe` Service and counts which pod answered each one. The path `/hostname` returns the name of the pod that served the request. Any `curl` options you add are passed on:

```sh
count_pods() { for i in $(seq 1 8); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s "$@" | grep -o '"probe-[^"]*"'
done | sort | uniq -c; }
HOSTNAME_URL=http://probe:8000/hostname
```

Now hash a cookie called `session`, with a `ttl`. Save this as `destinationrule-probe.yaml`:

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
        httpCookie:
          name: session
          ttl: 3600s
```

Apply it:

```sh
kubectl apply -f destinationrule-probe.yaml
```

Then send one request without a cookie, and look at the response headers:

```sh
kubectl exec -n starfleet deploy/shuttle -- curl -s -i $HOSTNAME_URL | grep -i -E 'set-cookie|hostname'
```

```text
set-cookie: session="3413e938a0751f42"; Max-Age=3600; HttpOnly
  "hostname": "probe-v2-58767cc46-9srsh"
```

The sidecar proxy created a cookie called `session`, valid for 3600 seconds. The application did not send it. Now send 8 requests that carry a cookie:

```sh
count_pods -b "session=abc123" $HOSTNAME_URL
```

```text
   8 "probe-v1-7888d6c6d5-v2s9n"
```

Every request with the same cookie reached the same pod.

### Remove the `ttl`

Delete the `ttl: 3600s` line from `destinationrule-probe.yaml`. Apply it:

```sh
kubectl apply -f destinationrule-probe.yaml
```

Then count how many `Set-Cookie` lines a new visitor gets:

```sh
kubectl exec -n starfleet deploy/shuttle -- curl -s -i $HOSTNAME_URL | grep -i -c 'set-cookie'
```

```text
0
```

The proxy no longer creates a cookie. Without `ttl`, a first-time visitor has nothing to hash, so the proxy spreads its requests like any other request.

## Sticky by source IP

The cookie needs a client that stores it. The next option needs nothing from the client at all. `useSourceIp: true` hashes the client's IP address, that is, the address the request came from.

### Pin every request from the `shuttle` pod

Save this as `destinationrule-probe.yaml`, replacing the old file:

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
        useSourceIp: true
```

Apply it:

```sh
kubectl apply -f destinationrule-probe.yaml
```

Then send 8 requests, without any header:

```sh
count_pods $HOSTNAME_URL
```

```text
   8 "probe-v1-7888d6c6d5-v2s9n"
```

All 8 requests from the `shuttle` pod landed on one pod. That is also the downside: every user behind one address lands on one pod. Requests that arrive through a gateway are the classic case, because they all come from the gateway's address.

## Sticky by query parameter

The last option sits in the URL. `httpQueryParameterName` hashes the value of one query parameter, such as `?user=alice`. It suits APIs that already carry the user id in the address.

### Pin by `?user=`

Save this as `destinationrule-probe.yaml`, replacing the old file:

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
        httpQueryParameterName: user
```

Apply it:

```sh
kubectl apply -f destinationrule-probe.yaml
```

Then send 8 requests with `?user=alice`, and 8 without it:

```sh
count_pods "$HOSTNAME_URL?user=alice"
count_pods $HOSTNAME_URL
```

One run gave:

```text
   8 "probe-v2-58767cc46-9srsh"
   1 "probe-v1-7888d6c6d5-57cqj"
   2 "probe-v1-7888d6c6d5-6lfpq"
   3 "probe-v1-7888d6c6d5-v2s9n"
   2 "probe-v2-58767cc46-9srsh"
```

With the parameter, all 8 requests reached one pod. Without it, they spread.

> [!TIP]
> Put quotes around a URL with `?` in it. In zsh, `?` is a wildcard, and the shell stops with `no matches found` before `curl` even runs.

You now know four values to hash, and which kind of client each one suits. Only a cookie with `ttl` gives a first-time visitor something to hash. All the examples so far put the policy on the whole host; the open question is how to give one subset or one port a different policy.

## Common pitfalls

> [!WARNING]
> - **Expecting `httpCookie` to create a cookie without `ttl`.** Without `ttl`, Istio only hashes a cookie the client already has.
> - **Using `useSourceIp` behind a gateway or a shared address.** Every request arrives with the same address, so one pod takes all the requests.
> - **Leaving a query-parameter URL unquoted in zsh.** `?` is a wildcard there.
> - **Expecting stickiness to keep a user on one version in a weighted split.** The proxy picks the subset first, for every request. Stickiness only chooses among that subset's pods. To keep a user on one version, route by header in the `VirtualService`, the Istio object that holds routing rules.
