# Verify TLS Origination And Configure Mutual TLS

A `200` alone does not prove TLS (Transport Layer Security) origination. The external server might simply have accepted a plain HTTP request. This part collects real proof from both ends of the connection. It then uses the request visibility you gained to add a timeout. Finally, it shows what changes when the external server also wants a certificate from your side.

The commands below need three objects for the host `httpbin.org`, all named `httpbin` in `starfleet`. They are a `ServiceEntry` with port `80` (`HTTP`) and port `443` (`HTTPS`), a `VirtualService` that routes port `80` to port `443`, and a `DestinationRule` that sets `tls.mode: SIMPLE` with `sni: httpbin.org` under `portLevelSettings` for port `443`.

## Proof from the destination

The most direct proof is the destination's own view: ask the external service how the request arrived. `httpbin.org/get` returns the full URL it received, including the scheme (`http` or `https`).

<!-- astrona:playground:renew -->

Send a plain HTTP request from the shuttle and filter the response:

```sh
kubectl exec -n starfleet deploy/shuttle -- curl -s http://httpbin.org/get | grep -e '"url"' -e Decorator
```

You should see:

```text
    "X-Envoy-Decorator-Operation": "httpbin.org:443/*", 
  "url": "https://httpbin.org/get"
```

The shuttle called `http://`, and httpbin.org received `https://`. The shuttle's sidecar proxy added the header `X-Envoy-Decorator-Operation`, and it names the route the proxy used: `httpbin.org:443`. So the TLS was added between the application and the server, by the proxy.

## Proof from the proxy

The second proof is in the proxy's own configuration. Each port of `httpbin.org` is an Envoy cluster in the shuttle's proxy, that is, the proxy's group of endpoints for one host and port. A cluster that uses TLS has a **transport socket** named `envoy.transport_sockets.tls`, and it carries the `sni` name you set. SNI (Server Name Indication) is the server name the client sends at the start of the TLS handshake.

List the clusters for `httpbin.org`, then look inside the one for port `443`:

```sh
istioctl proxy-config cluster deploy/shuttle -n starfleet --fqdn httpbin.org
istioctl proxy-config cluster deploy/shuttle -n starfleet --fqdn httpbin.org --port 443 -o json | grep -A3 '"transportSocket"'
istioctl proxy-config cluster deploy/shuttle -n starfleet --fqdn httpbin.org --port 443 -o json | grep '"sni"'
```

You should see:

```text
SERVICE FQDN     PORT     SUBSET     DIRECTION     TYPE           DESTINATION RULE
httpbin.org      80       -          outbound      STRICT_DNS     httpbin.starfleet
httpbin.org      443      -          outbound      STRICT_DNS     httpbin.starfleet
        "transportSocket": {
            "name": "envoy.transport_sockets.tls",
            "typedConfig": {
                "@type": "type.googleapis.com/envoy.extensions.transport_sockets.tls.v3.UpstreamTlsContext",
                "sni": "httpbin.org"
```

Both clusters use the `httpbin` `DestinationRule` in `starfleet`. Only port `443` has the TLS transport socket, and it sends the SNI name `httpbin.org`.

If you leave `sni` out, Istio 1.30.5 sets `autoSni: true` on the cluster instead, and takes the name from the request's `Host` header. That works for `httpbin.org`. It does not work when the application calls an IP address, because the server then receives an IP address as its name. So set `sni` yourself.

`istioctl analyze` checks your configuration for known problems. Run it for the namespace:

```sh
istioctl analyze -n starfleet
```

```text
Warning [IST0129] (DestinationRule starfleet/httpbin) DestinationRule starfleet/httpbin in namespace starfleet has TLS mode set to SIMPLE but no caCertificates are set to validate server identity for host: httpbin.org at port number:443
```

`IST0129` is a warning, not an error. Without `caCertificates`, the proxy checks the server's certificate against its default trust store: the same public certificate authorities that a web browser trusts. Set `caCertificates` when you want to trust only one specific certificate authority. The warning is also a useful clue when you troubleshoot, because it names the port that has the `tls` block.

## Use the request visibility

Now that the proxy can read each request again, request-level features work for the external service. A route `timeout` is one of them: if no response arrives within that time, the proxy stops waiting and returns an error to the application.

Add `timeout: 2s` to the `VirtualService`. Save this as `virtualservice-httpbin-timeout.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: httpbin
  namespace: starfleet
spec:
  hosts:
  - httpbin.org
  http:
  - match:
    - port: 80
    timeout: 2s
    route:
    - destination:
        host: httpbin.org
        port:
          number: 443
```

Apply it:

```sh
kubectl apply -f virtualservice-httpbin-timeout.yaml
```

Then check the result. Ask httpbin.org for a response that takes 5 seconds, and read the access log:

```sh
kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" http://httpbin.org/delay/5
kubectl logs -n starfleet deploy/shuttle -c istio-proxy --tail=1
```

You should see:

```text
504
[2026-10-08T22:57:16.891Z] "GET /delay/5 HTTP/1.1" 504 UT response_timeout - "-" 0 24 2006 - "-" "curl/8.11.1" "ef018075-d6dc-4114-b108-7af55cfac8a0" "httpbin.org" "54.159.186.149:443" outbound|443||httpbin.org 10.244.0.6:49352 100.51.105.232:80 10.244.0.6:46478 - -
```

The shuttle's proxy stopped waiting after about 2 seconds (`2006` milliseconds) and answered `504` with the response flag `UT` (upstream request timeout). On a request that the application encrypted itself, this rule could never take effect. Retries, fault injection and header-based routing now work in the same way.

## Mutual TLS to an external service

So far the proxy checks the server's certificate, but the server does not check yours. `SIMPLE` is that ordinary one-way HTTPS. Some external services also require a certificate from the client, so both sides verify each other. That is `mode: MUTUAL` (mutual TLS), and the proxy then needs a client certificate and its private key.

There are two ways to give them to the proxy. These parts of a `DestinationRule` show both. You do not apply them, because your playground has no external service that asks for a client certificate:

```yaml
      # by file path, mounted into the PROXY container
      tls:
        mode: MUTUAL
        clientCertificate: /etc/certs/client.pem
        privateKey: /etc/certs/client-key.pem
        caCertificates: /etc/certs/ca.pem
        sni: api.partner.example
```

```yaml
      # by Kubernetes secret
      tls:
        mode: MUTUAL
        credentialName: partner-client-cert
        sni: api.partner.example
```

Three facts matter here:

- **File paths point into the proxy container**, not the application container. The files must be mounted into the sidecar, which needs a pod annotation and a restart. That is one reason the secret form is easier.
- **On a sidecar, `credentialName` reads a Kubernetes secret from the namespace of the workload** that sends the request. Every namespace that calls the external service needs its own copy of the secret.
- **`caCertificates` sets which certificate authority the proxy trusts for the server.** `insecureSkipVerify: true` turns the server certificate check off. Use it only as a test shortcut, never as normal configuration.

Everything else stays the same. `MUTUAL` is still TLS origination, still goes under `portLevelSettings`, and is still invisible to the application.

## Where to originate TLS

With TLS origination in the sidecar, every calling pod does its own encryption. For `SIMPLE` that costs nothing, because there is no secret to store. For `MUTUAL`, every pod that calls the external service needs access to the client certificate. An egress gateway, an Envoy proxy at the edge of the mesh that handles traffic leaving the cluster, can do the same TLS origination in one place instead:

| | Sidecar origination | Egress gateway origination |
| --- | --- | --- |
| Client certificate stored in | every calling workload's namespace | the gateway's namespace only |
| Renewing the certificate | everywhere at once | one secret |
| A compromised pod | holds the client certificate | holds nothing |
| Network hops | direct | one extra |
| One place to check all outbound traffic | no | yes |

For an external service that requires a client certificate, the first row usually decides it.

You can now prove TLS origination from both ends: the destination reports `"url": "https://..."`, and the proxy's port `443` cluster has `envoy.transport_sockets.tls` with the `sni` name. You have seen a request-level feature, a timeout, work on an external call. You also know what `MUTUAL` adds and where its client certificate must be stored.

## Common pitfalls

> [!WARNING]
> - **Reading a `200` as proof.** Check the destination's view (`"url": "https://..."`) and the proxy's cluster (`envoy.transport_sockets.tls`).
> - **Leaving out `sni`.** Istio then takes the name from the `Host` header. If the application calls an IP address, the server receives an IP address as its name.
> - **Thinking the request is now plain on the network.** Only the hop inside the pod, between the application and its own sidecar proxy, is plain.
> - **`MUTUAL` with file paths the sidecar cannot read.** Mount the files into the proxy container, or use `credentialName`.
> - **Leaving `insecureSkipVerify: true` in place.** It turns off the server certificate check. Use `caCertificates` instead.

## Your mission: Originate TLS To A TLS-Only External Service Lab

You can now build TLS origination, prove it from both ends, and explain what `MUTUAL` changes. The lab asks you to build all three objects from scratch for a server outside the mesh that only accepts TLS, while the client keeps sending plain HTTP.

The lab runs in its own cluster, so first pause your playground. Nothing in it is lost:

```sh
astrona stop ats-014-playground-070-02
```

Then start the lab:

```sh
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-070/module-02/labs/lab-01
```

The task is on the next page. Solve it on your own first. When you think you are done, send it for grading:

```sh
astrona submit -c sections/section-070/module-02/labs/lab-01
```

When the lab is done, remove it and start your playground again:

```sh
astrona destroy ats-014-lab-070-02
astrona start ats-014-playground-070-02
```
