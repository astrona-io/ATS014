# Sticky Cookies And Other Hash Sources

Astronaut, a header only works when the sender adds it. A browser usually cannot. This part shows the three other things you can hash: a cookie, which Istio can even hand out itself, the sender's IP address, and a query parameter. Each one fits a different kind of traffic, and each has its own trap.

The commands below need the `count_pods` helper pasted into your terminal.

## Sticky by cookie

A browser keeps cookies and sends them back on every visit, so for browser traffic a cookie is usually the best thing to hash. The `httpCookie` field takes a `name`, and an optional `ttl`.

The important detail is `ttl`. **Setting `ttl` makes the sidecar create the cookie** when a signal arrives without one: it adds a `Set-Cookie` header to the answer, and the browser sends the cookie back from then on. That closes the "nothing to hash" gap for a first-time visitor. `ttl` is also how long the cookie lasts.

Leave `ttl` out, and Istio only hashes a cookie the sender already has. That is the right choice when another part of your system owns the session cookie.

<!-- astrona:playground:renew -->

### Let the sidecar hand out a cookie

Save this as `destinationrule-probe.yaml`:

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

Then send one signal without a cookie, and look at the answer's headers:

```sh
kubectl exec -n starfleet deploy/shuttle -- curl -s -i $HOSTNAME_URL | grep -i -E 'set-cookie|hostname'
```

```text
set-cookie: session="3413e938a0751f42"; Max-Age=3600; HttpOnly
  "hostname": "probe-v2-58767cc46-9srsh"
```

The sidecar created a cookie called `session`, valid for 3600 seconds. Now send 8 signals that carry a cookie:

```sh
count_pods -b "session=abc123" $HOSTNAME_URL
```

```text
   8 "probe-v1-7888d6c6d5-v2s9n"
```

Every signal with the same cookie reached the same ship.

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

No cookie is handed out any more. Without `ttl`, a first-time visitor has nothing to hash and is spread like any other signal.

## Sticky by source IP

`useSourceIp: true` hashes the sender's IP address: where in the solar system the signal came from. No header or cookie is needed.

### Pin every signal from the shuttle

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

Then send 8 signals, without any header:

```sh
count_pods $HOSTNAME_URL
```

```text
   8 "probe-v1-7888d6c6d5-v2s9n"
```

All 8 signals from the shuttle landed on one ship. That is also the downside: every user behind one address lands on one ship. Signals that arrive through a gateway are the classic case, because they all come from the gateway's address.

## Sticky by query parameter

`httpQueryParameterName` hashes the value of one query parameter in the URL, such as `?user=alice`. It suits APIs that already carry the user id in the address.

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

Then send 8 signals with `?user=alice`, and 8 without it:

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

With the parameter, all 8 signals reached one ship. Without it, they spread.

> [!TIP]
> Put quotes around a URL with `?` in it. In zsh, `?` is a wildcard, and the shell stops with `no matches found` before `curl` even runs.

## Common pitfalls

> [!WARNING]
> - **Expecting `httpCookie` to create a cookie without `ttl`.** Without `ttl`, Istio only hashes a cookie the sender already has.
> - **Using `useSourceIp` behind a gateway or a shared address.** Every sender arrives with the same address, so one ship takes all the signals.
> - **Leaving a query-parameter URL unquoted in zsh.** `?` is a wildcard there.
> - **Expecting stickiness to keep a user on one version in a weighted split.** The subset is picked first, for every signal. Stickiness only chooses among that subset's ships. To keep a user on one version, route by header in the flight plan.

> *A header, a cookie, an address or a query parameter: whatever you hash decides who stays together. Only a cookie with `ttl` gives a first-time visitor something to hash.*
