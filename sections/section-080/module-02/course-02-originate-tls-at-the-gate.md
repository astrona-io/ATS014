# Originate TLS At The Gate

The route through the departure gate works, but the signal leaves unsealed. In this part you add the fifth object, the one that puts the TLS lock on, and you see why it names the outside host and not the gate.

The commands below need the `ServiceEntry` `httpbin-org`, the `Gateway` `departure-gate`, the `DestinationRule` `departure-gate` and the `VirtualService` `httpbin-org-via-gate` applied in your playground, and the helpers from the landing page pasted into your terminal.

## The lock belongs to the destination

A `DestinationRule` is a set of docking instructions for one destination. They belong to the planet you approach, and **the ship doing the approach follows them**. Istio works the same way: the traffic policy of a `DestinationRule` is used by whichever proxy calls the host it names.

Who calls `httpbin.org` on port `443`? Not the shuttle's sidecar: stage 1 sends its signal to the gate. The **gate** calls `httpbin.org`. So the TLS settings go in a `DestinationRule` for `host: httpbin.org`, and the gate is the proxy that follows them.

Three fields do the work:

| Field | What it does |
| --- | --- |
| `portLevelSettings` with port `443` | applies the TLS settings to port `443` only, so plain port `80` stays plain |
| `tls.mode: SIMPLE` | starts an ordinary TLS connection, the same kind a browser makes, and checks the server's certificate |
| `tls.sni` | the host name the gate says during the TLS handshake. Many servers host several names on one address, and use this one to pick the right certificate |

<!-- astrona:playground:renew -->

### Put the lock on at the gate

Save this as `destinationrule-httpbin-org-tls.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: httpbin-org-tls
  namespace: starfleet
spec:
  host: httpbin.org
  trafficPolicy:
    portLevelSettings:
    - port:
        number: 443
      tls:
        mode: SIMPLE
        sni: httpbin.org
```

Apply it:

```sh
kubectl apply -f destinationrule-httpbin-org-tls.yaml
```

Then send the same plain signal again, and read the gate's flight log:

```sh
call_httpbin
log_gate
```

You should see (log line trimmed):

```text
  "url": "https://httpbin.org/get"
200
"GET /get HTTP/2" 200 - via_upstream - "-" 0 1077 732 731 "10.244.0.7" "curl/8.11.1" ... "httpbin.org" "54.159.186.149:443" outbound|443||httpbin.org ...
```

The shuttle still sent `http://`, but `httpbin.org` reports that it was called on `https://`. The gate's line shows a readable HTTP request (method, path and status), sent on to port `443`. The gate can read the request because it received it plain. Then it put the lock on as the signal left.

## When the onward port is wrong

Stage 2's port is the line that decides whether the lock is used at all. The TLS settings only cover port `443`. Route stage 2 to port `80`, and the gate sends the signal on port `80` with no settings, so it leaves plain.

### Send stage 2 to port 80

This is a change to one field, so a short `kubectl patch` is enough. It sets the port of stage 2, the second rule in the `http` list, to `80`:

```sh
kubectl patch virtualservice httpbin-org-via-gate -n starfleet --type json \
  -p '[{"op":"replace","path":"/spec/http/1/route/0/destination/port/number","value":80}]'
```

Then call again and read the gate's flight log:

```sh
call_httpbin
log_gate
```

You should see (log line trimmed):

```text
  "url": "http://httpbin.org/get"
200
"GET /get HTTP/2" 200 - via_upstream - "-" 0 1075 256 255 "10.244.0.7" "curl/8.11.1" ... "httpbin.org" "98.89.203.252:80" outbound|80||httpbin.org ...
```

Still `200`, and that is the danger. `httpbin.org` also answers plain HTTP on port `80`, so nothing fails. Only the `url` field and the gate's upstream port `80` show that the signal left the solar system without a lock. A server that only speaks TLS would have refused it. A server that speaks both quietly accepts it.

Put stage 2 back on port `443`:

```sh
kubectl apply -f virtualservice-httpbin-org-via-gate.yaml
```

## Common pitfalls

> [!WARNING]
> - **Stage 2 routed to port 80.** The TLS settings for port `443` are never used. Against a server that also speaks plain HTTP, the call still returns `200`, unsealed.
> - **`tls` at the top of `trafficPolicy`.** It then covers every port of the host, port `80` included. Put it under `portLevelSettings` for `443`.
> - **No `sni`.** The gate is the TLS client now, so it must say which host it wants. A server with many names may hand over the wrong certificate or refuse.
> - **Trusting the `200`.** Read where the signal was sealed: the `url` field, and the upstream port in the gate's flight log.

> *The lock goes in a `DestinationRule` for the outside host, on port 443. The gate follows it, because the gate is the proxy that calls that host.*
