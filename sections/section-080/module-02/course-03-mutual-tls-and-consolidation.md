# Mutual TLS And The Consolidation Argument

With `SIMPLE`, moving origination to the gateway is mostly about keeping things in one place. With `MUTUAL` (mutual TLS: a secret handshake both sides check before they talk), it becomes the reason the feature exists. This part covers that case, and the module's pitfalls.

## `MUTUAL` at the gateway

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: originate-mtls-for-partner
  namespace: egwtls-demo
spec:
  host: api.partner.example
  trafficPolicy:
    portLevelSettings:
      - port:
          number: 443
        tls:
          mode: MUTUAL
          credentialName: partner-client-cert
          sni: api.partner.example
```

One field changes from `SIMPLE`, and one is added. Everything else — the five objects, the port numbers, the `portLevelSettings` placement — is identical.

## Where `credentialName` is read from

This is the detail that matters operationally and is the most likely thing to be tested.

`credentialName` names a Kubernetes secret. **It is read from the namespace of the proxy that loads it** — which for gateway origination means the **gateway's** namespace, `istio-system` for the default egress gateway.

That is the same rule as the `Ingress` TLS secret in section 060 module 2, and for the same reason. A spaceship can only read secrets stored on its own planet (namespace), and the ship doing the reading is the gateway.

The failure is silent, like a signal lost in deep space. A `credentialName` pointing at a secret that is not there gives you a listener that never comes up, calls that fail, and **no message naming the cause**. When gateway TLS "just does not work", check which namespace the secret is in before anything else.

The secret itself is an ordinary TLS secret plus, for `MUTUAL`, the CA to verify the server:

```sh
kubectl -n istio-system create secret generic partner-client-cert \
  --from-file=tls.crt=client.pem \
  --from-file=tls.key=client-key.pem \
  --from-file=ca.crt=partner-ca.pem
```

Because the secret is loaded over SDS, the gateway proxy can be asked what it currently holds — which turns "is the credential there" from a guess into a listing.

> [!TIP]
> **Try it — the certificates the egress gateway has actually loaded**
>
> ```sh
> istioctl proxy-config secret deploy/istio-egressgateway -n istio-system
> ```
>
> Expect something like:
>
> ```text
> RESOURCE NAME   TYPE         STATUS   VALID CERT   SERIAL NUMBER                      NOT AFTER              NOT BEFORE
> default         Cert Chain   ACTIVE   true         b52abac6bbaa2576360b7caa2ba756bb   2026-09-30T18:30:29Z   2026-09-29T18:28:29Z
> ROOTCA          CA           ACTIVE   true         45233b55ed568eac0a223c2ba7c3e403   2036-09-26T18:30:19Z   2026-09-29T18:30:19Z
> ```
>
> `default` and `ROOTCA` are the gateway's own mesh identity and are always there — note the one-day lifetime on `default`, which is the workload certificate Istio rotates automatically, against ten years for the root. A secret named by `credentialName` appears as an additional row once it is loaded — and a `credentialName` pointing at a secret in the wrong namespace simply never shows up here, with nothing else reporting the problem. That absence is the diagnosis.

## The comparison

Here is the argument for the whole section, in one table:

| | Sidecar origination (section 070) | Gateway origination (this module) |
| --- | --- | --- |
| Certificate stored in | **every** calling workload's namespace | the gateway's namespace only |
| Rotation | everywhere at once, coordinated | one secret |
| A compromised application pod | holds the client certificate | holds nothing |
| Adding a new caller | provision the certificate to it | nothing to do |
| Auditable exit point | no — every sidecar | yes — one log |
| Source address partners allow-list | every node | the gateway's |
| Network hops | direct | one extra |
| Objects per external host | 3 | 5 |
| Component on the critical path | none | the gateway |

The first four rows are the case for the gateway. The last three are the case against it: an extra hop, more objects, and one gate that every signal depends on — the Death Star risk, if you run it with too few replicas. For a `SIMPLE` external API with no credentials, section 070's three objects are simpler and perfectly good. For a partner API with a client certificate, the first row usually decides it on its own.

## Where this leaves the course

The five objects in this module use something from almost every section:

| From | Used here as |
| --- | --- |
| section 010 | `VirtualService` `http` rules, matching, first-match evaluation |
| section 030 | `trafficPolicy` precedence — `portLevelSettings` beating the host level |
| section 060 | `Gateway` with a pod `selector`, and `gateways:` binding |
| section 070 | `ServiceEntry`, `location`, `resolution`, protocol selection |
| section 080 module 1 | the two-stage `VirtualService` and the reserved `mesh` name |

If that combination reads naturally, astronaut, your traffic-management training is complete.

## Common pitfalls

> [!WARNING]
> **Applying the origination `DestinationRule` to the gateway's host.** It must target the **external** host. Traffic policy is applied by whichever proxy calls that destination — the gateway — so pointing it at the gateway's own Service originates nothing.
>
> **Routing stage 2 to port 80 of the external host.** Origination needs the destination port to be 443. The listener stays on 80; only the onward route changes.
>
> **Declaring only port 80 in the `ServiceEntry`.** Stage 2 has nowhere to send the traffic.
>
> **`tls` at the top of `trafficPolicy` instead of under `portLevelSettings`.** It would apply to port 80 as well.
>
> **Missing `sni`.** The gateway is the TLS client now; multi-tenant endpoints will reject or mis-serve the handshake.
>
> **A `credentialName` secret in the wrong namespace.** It is read from the **gateway's** namespace, and a missing secret fails silently.
>
> **Assuming the sidecar still originates.** It does not — and `istioctl proxy-config cluster` on both proxies shows you exactly which one holds the TLS context.
>
> **Confusing the two `DestinationRule` objects.** One names the gateway Service and carries an empty subset; the other names the external host and carries the TLS settings. They do unrelated jobs.

> *The client certificate lives wherever the proxy that presents it lives — which is the entire operational argument for doing this at the gateway.*
