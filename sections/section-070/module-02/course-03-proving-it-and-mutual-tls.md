# Proving It, And Mutual TLS

A `200` does not prove origination — the external service might simply have accepted plaintext. This part is the evidence, then what changes when the external service also wants a certificate from you.

## Evidence from the destination

The honest proof comes from the **destination's own view** of the signal: ask the other planet what it received. Many HTTP services report the scheme they were reached over in an `X-Forwarded-Proto` header, and `httpbin.org/headers` echoes back everything it received.

<!-- astrona:playground:renew -->

> [!TIP]
> **Try it — ask the external service what it saw**
>
> ```sh
> kubectl -n tlsorig-demo exec deploy/tester -- \
>   curl -s --max-time 15 http://httpbin.org/headers | grep -i 'X-Forwarded-Proto'
> ```
>
> Expect something like:
>
> ```text
>     "X-Forwarded-Proto": "https",
> ```
>
> The application sent `http://`; the external service received `https`. The upgrade happened in between, inside the sidecar. That single header is the cleanest evidence available without packet capture.

## Evidence from the mesh

The other half is that the visibility you paid for is back. The same access log that showed `"- - -"` in Part 1 now shows a request.

> [!TIP]
> **Try it — the request is a request again**
>
> ```sh
> kubectl -n tlsorig-demo exec deploy/tester -- \
>   curl -s -o /dev/null --max-time 15 http://httpbin.org/get
> kubectl -n tlsorig-demo logs deploy/tester -c istio-proxy --tail=2 | tail -1
> istioctl proxy-config cluster deploy/tester -n tlsorig-demo --fqdn httpbin.org -o json \
>   | grep -i -A3 transportSocket | head -8
> ```
>
> Expect something like:
>
> ```text
> [2026-09-27T12:44:18.907Z] "GET /get HTTP/1.1" 200 - via_upstream - "-" 0 512 198 197 "-" "curl/8.5.0" ... "httpbin.org:443"
> "transportSocket": {
>   "name": "envoy.transport_sockets.tls",
> ```
>
> A method, a path and a status where there were dashes — which means every layer-7 feature in this course now applies to this external call. And `transportSocket` with the TLS name on the cluster is the proxy-side confirmation that the connection to port 443 is encrypted.

Those two checkpoints together are the complete proof: the destination saw HTTPS, and the mesh saw a request. Either alone is ambiguous.

## Mutual TLS to an external service

`SIMPLE` means the proxy verifies the server's certificate — ordinary one-way HTTPS. When the external service also requires a **client** certificate, both sides must check a secret handshake, the mode is `MUTUAL`, and the proxy needs credentials.

There are two ways to supply them:

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
# by Kubernetes secret — the more manageable form
tls:
  mode: MUTUAL
  credentialName: partner-client-cert
  sni: api.partner.example
```

Three things to know:

- **The file paths refer to the proxy container**, not the application. The certificate must be mounted into the sidecar, which means an annotation on the pod spec and a redeploy — one of the reasons the secret form is preferred.
- **`credentialName` reads a secret from the workload's own namespace** when used on a sidecar. In section 080, where origination moves to the gateway, the same field reads from the *gateway's* namespace — same field, different reader, so the secret moves with it.
- **`caCertificates` is how you pin the server's issuer.** Without it the proxy uses its default trust store. `insecureSkipVerify` exists and should be treated as a debugging tool, not a configuration.

Everything else is unchanged: `MUTUAL` is still origination, still under `portLevelSettings`, still transparent to the application. Only the handshake differs.

## The placement question

This is the decision section 080 module 2 exists to make, and it is worth framing now.

With sidecar origination, **every calling ship seals its own signals**: every calling workload originates its own TLS. For `SIMPLE` that is fine — there is no secret. For `MUTUAL` it means the client certificate must be available to every pod that calls the service:

| | Sidecar origination (this module) | Gateway origination (section 080) |
| --- | --- | --- |
| Certificate stored in | every calling workload's namespace | the gateway's namespace only |
| Rotation | everywhere at once | one secret |
| Blast radius of a compromised pod | it holds the client certificate | it holds nothing |
| Network hops | direct | one extra |
| Single place to audit egress | no | yes |

For a partner API with a client certificate, that first row is usually the whole argument.

## Common pitfalls

> [!WARNING]
> **Declaring only port 443 in the `ServiceEntry`.** The port-80 redirect has nothing to match and the call fails.
>
> **Putting `tls` at the top of `trafficPolicy` instead of under `portLevelSettings`.** It applies to port 80 as well and breaks the plaintext side — a 503 from an object that looks correct.
>
> **Missing `sni`.** Shared-hosting endpoints present the wrong certificate or reject the handshake. It may work in testing against a single-certificate host and fail in production.
>
> **The application still calling `https://`.** The sidecar sees an encrypted stream and none of this applies. It is the one prerequisite the mesh cannot supply.
>
> **Assuming the wire traffic is now plaintext.** Only the hop inside the pod, between the app container and its own sidecar, is in the clear.
>
> **Expecting `MUTUAL` to work with paths the sidecar cannot read.** The certificate must be mounted into the proxy container, or supplied via `credentialName`.
>
> **Reading a `200` as proof.** Check `X-Forwarded-Proto` at the destination and `transportSocket` on the cluster.
>
> **Forgetting the `VirtualService` entirely.** Traffic stays on port 80, the external service refuses plaintext, and the `DestinationRule` never gets a chance to act.

> *A `200` proves the call worked; `X-Forwarded-Proto: https` at the destination proves the sidecar did the handshake.*
