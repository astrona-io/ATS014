# Proving It, And Mutual TLS

Astronaut, a `200` alone does not prove origination. The outside server might simply have accepted a plain signal. This part collects real evidence from both ends, uses the visibility you won, and then shows what changes when the outside server wants a certificate from you too.

The commands below need the `httpbin` `ServiceEntry` (ports `80` HTTP and `443` HTTPS), the `VirtualService` that moves port `80` to `443`, and the `DestinationRule` that seals port `443` with `sni: httpbin.org`, all applied in your playground in `starfleet`.

## Evidence from the destination

The most honest proof is the destination's own view: ask the other planet how the signal arrived. `httpbin.org/get` echoes the full address it was reached on, including the scheme.

<!-- astrona:playground:renew -->

### Ask httpbin.org what it saw

Send an open signal and filter the answer:

```sh
kubectl exec -n starfleet deploy/shuttle -- curl -s http://httpbin.org/get | grep -e '"url"' -e Decorator
```

You should see:

```text
    "X-Envoy-Decorator-Operation": "httpbin.org:443/*", 
  "url": "https://httpbin.org/get"
```

The shuttle called `http://`, and httpbin.org was reached on `https://`. The header `X-Envoy-Decorator-Operation` was added by the shuttle's proxy, and it names the route it used: `httpbin.org:443`. The seal was added in between, by the proxy.

## Evidence from the proxy

The second proof is in the proxy's own orders. Each port of `httpbin.org` is an Envoy cluster in the shuttle's proxy. A cluster that seals its connections has a **transport socket** named `envoy.transport_sockets.tls`, and it carries the `sni` name you set.

### Read the shuttle's clusters for httpbin.org

List the clusters, then look inside the one for port `443`:

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

Both clusters use the `httpbin` `DestinationRule` in `starfleet`. Only port `443` has the TLS transport socket, and it sends the SNI name `httpbin.org`. If you leave `sni` out, Istio 1.30.5 sets `autoSni: true` on the cluster instead, and takes the name from the signal's `Host` header. That works for `httpbin.org`, but not when the application calls an IP address, so set `sni` yourself.

Ask `istioctl analyze` too:

```sh
istioctl analyze -n starfleet
```

```text
Warning [IST0129] (DestinationRule starfleet/httpbin) DestinationRule starfleet/httpbin in namespace starfleet has TLS mode set to SIMPLE but no caCertificates are set to validate server identity for host: httpbin.org at port number:443
```

`IST0129` is a warning, not an error. Without `caCertificates`, the proxy checks the server's certificate against its default trust store, the same public certificate authorities a web browser trusts. Set `caCertificates` when you want to trust only one specific issuer. The warning is also a handy clue: it names the port that carries the `tls` block.

## Use what you won

The proxy can read the request again, so request-level features work for the outside planet. A route `timeout` is the abort window: no reply by then, and the proxy gives the signal up.

### Add a timeout to the outside call

Add `timeout: 2s` to the flight plan. Save this as `virtualservice-httpbin-timeout.yaml`:

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

Then ask httpbin.org for an answer that takes 5 seconds, and read the flight log:

```sh
kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" http://httpbin.org/delay/5
kubectl logs -n starfleet deploy/shuttle -c istio-proxy --tail=1
```

You should see:

```text
504
[2026-10-08T22:57:16.891Z] "GET /delay/5 HTTP/1.1" 504 UT response_timeout - "-" 0 24 2006 - "-" "curl/8.11.1" "ef018075-d6dc-4114-b108-7af55cfac8a0" "httpbin.org" "54.159.186.149:443" outbound|443||httpbin.org 10.244.0.6:49352 100.51.105.232:80 10.244.0.6:46478 - -
```

The shuttle's proxy gave up after about 2 seconds (`2006` milliseconds) and answered `504` with the flag `UT` (upstream timeout). On a signal the application sealed itself, this rule could never fire. Retries, fault injection and header routing work the same way now.

## Mutual TLS to an outside service

`SIMPLE` is ordinary one-way HTTPS: the proxy checks the server's certificate. Some partners also want a certificate from **you**, so both sides check a secret handshake. That is `mode: MUTUAL`, and the proxy then needs a client certificate and its private key.

There are two ways to give them to the proxy. These pieces of a `DestinationRule` show both (you do not apply them; your playground has no partner that asks for a client certificate):

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

Three facts to remember:

- **File paths point into the proxy container**, not the application container. The files must be mounted into the sidecar, which takes a pod annotation and a restart. That is one reason the secret form is easier.
- **On a sidecar, `credentialName` reads a secret from the namespace of the workload** that sends the signal. Every namespace that calls the partner needs its own copy of the secret.
- **`caCertificates` pins the server's issuer.** `insecureSkipVerify: true` turns the server check off. Treat it as a test shortcut, never as normal configuration.

Everything else stays the same: `MUTUAL` is still origination, still under `portLevelSettings`, and still invisible to the application.

## Where the seal should be added

With origination in the sidecar, every calling ship seals its own signals. For `SIMPLE` that costs nothing, because there is no secret. For `MUTUAL` the client certificate must be available to every pod that calls the partner. An egress gateway, the departure gate of the solar system, can do the same origination in one place instead:

| | Sidecar origination | Egress gateway origination |
| --- | --- | --- |
| Client certificate stored in | every calling workload's namespace | the gateway's namespace only |
| Renewing the certificate | everywhere at once | one secret |
| A broken-into pod | holds the client certificate | holds nothing |
| Network hops | direct | one extra |
| One place to check all outgoing signals | no | yes |

For a partner that wants a client certificate, the first row usually decides it.

## Common pitfalls

> [!WARNING]
> - **Reading a `200` as proof.** Check the destination's view (`"url": "https://..."`) and the proxy's cluster (`envoy.transport_sockets.tls`).
> - **Leaving out `sni`.** Istio then takes the name from the `Host` header. If the application calls an IP address, the server gets an IP address as its name.
> - **Thinking the signal is now open on the wire.** Only the hop inside the pod, between the application and its own sidecar, is plain.
> - **`MUTUAL` with file paths the sidecar cannot read.** Mount the files into the proxy container, or use `credentialName`.
> - **Leaving `insecureSkipVerify: true` in place.** It switches off the server check. Use `caCertificates` instead.

> *A `200` proves the call worked. `"url": "https://..."` at the destination and a TLS transport socket on the cluster prove the proxy added the seal.*

## Your mission: Seal Signals To A Secure Planet Lab

You can now build TLS origination, prove it from both ends, and explain what `MUTUAL` changes. Now prove it in a graded mission: build all three objects from scratch for a planet that only accepts sealed signals, while your client keeps sending open ones.

The mission runs in its own training solar system, so first pause your playground. Nothing in it is lost:

```sh
astrona stop ats-014-playground-070-02
```

Then start the mission:

```sh
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-070/module-02/labs/lab-01
```

Read the task in [`question.md`](./labs/lab-01/question.md) and solve it on your own first. When you think you are done, send it for grading:

```sh
astrona submit -c sections/section-070/module-02/labs/lab-01
```

When the mission is done, remove it and wake your playground up again:

```sh
astrona destroy ats-014-lab-070-02
astrona start ats-014-playground-070-02
```
