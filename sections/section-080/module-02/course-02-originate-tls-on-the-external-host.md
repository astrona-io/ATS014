# Originate TLS On The External Host

A request from the `shuttle` pod can now reach `httpbin.org` through the egress gateway, but it leaves the cluster as plain text, and `httpbin.org` rejects it with `400`. In this part you add the fifth object, the `DestinationRule` that turns on TLS (Transport Layer Security) for that last hop. You also see why it names the external host and not the egress gateway, and why a wrong port can hide a missing TLS connection behind a `200`.

The commands below need the `ServiceEntry` `httpbin-org`, the `Gateway` `departure-gate`, the `DestinationRule` `departure-gate` and the `VirtualService` `httpbin-org-via-gate` applied in your playground, and the helper functions `call_httpbin` and `log_gate` defined in your terminal.

## The TLS settings belong to the host being called

A `DestinationRule` sets how a proxy connects to one host. Its traffic policy is used by **whichever proxy calls the host it names**. The rule itself does not say which proxy that is; the routing does.

So ask who calls `httpbin.org` on port `443`. It is not the shuttle's sidecar proxy, because rule 1 of the `VirtualService` sends the shuttle's request to the egress gateway. The **egress gateway** calls `httpbin.org`. The TLS settings therefore go in a `DestinationRule` for `host: httpbin.org`, and the egress gateway is the proxy that applies them.

Three fields do the work:

| Field | What it does |
| --- | --- |
| `portLevelSettings` with port `443` | applies the TLS settings to port `443` only, so port `80` stays plain |
| `tls.mode: SIMPLE` | opens an ordinary TLS connection, the same kind a browser opens, and checks the server's certificate |
| `tls.sni` | the host name the egress gateway sends in the TLS handshake (SNI, Server Name Indication). A server with several names on one address uses it to pick the right certificate |

<!-- astrona:playground:renew -->

Put these fields into a `DestinationRule` for `httpbin.org`. Save this as `destinationrule-httpbin-org-tls.yaml`:

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

Then send the same plain request again, and read the egress gateway's access log:

```sh
call_httpbin
log_gate
```

You should see (log line shortened):

```text
  "url": "https://httpbin.org/get"
200
"GET /get HTTP/2" 200 - via_upstream - "-" 0 1077 732 731 "10.244.0.7" "curl/8.11.1" ... "httpbin.org" "54.159.186.149:443" outbound|443||httpbin.org ...
```

The shuttle still sent `http://`, but `httpbin.org` reports that it was called on `https://`. The egress gateway's line shows a readable HTTP request (method, path and status), sent on to port `443`. The egress gateway can read the request because it received it as plain text. It started TLS only on the connection it opened to `httpbin.org`.

## When the onward port is wrong

The TLS settings only cover port `443`. That makes the port in rule 2 the field that decides whether TLS is used at all. If rule 2 sends the request to port `80`, the egress gateway uses the cluster for port `80`, which has no TLS settings, and the request leaves as plain text.

To see this, change the port of rule 2, the second entry in the `http` list, to `80`. This is a change to one field, so a short `kubectl patch` is enough:

```sh
kubectl patch virtualservice httpbin-org-via-gate -n starfleet --type json \
  -p '[{"op":"replace","path":"/spec/http/1/route/0/destination/port/number","value":80}]'
```

Then call again and read the egress gateway's access log:

```sh
call_httpbin
log_gate
```

You should see (log line shortened):

```text
  "url": "http://httpbin.org/get"
200
"GET /get HTTP/2" 200 - via_upstream - "-" 0 1075 256 255 "10.244.0.7" "curl/8.11.1" ... "httpbin.org" "98.89.203.252:80" outbound|80||httpbin.org ...
```

The status is still `200`, and that is the danger. `httpbin.org` also answers plain HTTP on port `80`, so nothing fails. Only the `url` field and the upstream port `80` in the egress gateway's log show that the request left the cluster without TLS. A server that only speaks TLS would have rejected it. A server that speaks both accepts it without any warning.

Put rule 2 back on port `443` by applying the saved file again:

```sh
kubectl apply -f virtualservice-httpbin-org-via-gate.yaml
```

You now know where the TLS settings go: in a `DestinationRule` for the external host, under `portLevelSettings` for port `443`, with `tls.mode: SIMPLE` and `sni`. You also know that a `200` alone does not prove TLS. The open question is whether the egress gateway is really the only proxy that received these TLS settings.

## Common pitfalls

> [!WARNING]
> - **Rule 2 sends the request to port 80.** The TLS settings for port `443` are never used. Against a server that also speaks plain HTTP, the call still returns `200`, without TLS.
> - **`tls` at the top of `trafficPolicy`.** It then covers every port of the host, port `80` included. Put it under `portLevelSettings` for `443`.
> - **No `sni`.** The egress gateway is the TLS client now, so it must say which host it wants. A server with many names may send the wrong certificate or reject the connection.
> - **Trusting the `200`.** Check where TLS started: the `url` field, and the upstream port in the egress gateway's access log.
