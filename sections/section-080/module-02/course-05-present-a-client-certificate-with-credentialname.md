# Present A Client Certificate With MUTUAL And credentialName

The partner server checks certificates in both directions, so the egress gateway needs two things: the partner's certificate authority (CA), to verify the partner server, and a client certificate, to prove its own identity. In this part you give the egress gateway both with `tls.mode: MUTUAL` and one field, `credentialName`. You then find out which namespace the certificate must be stored in, and why it matters.

The commands below need the four partner routing objects (the `ServiceEntry` `partner`, the `Gateway` and `DestinationRule` `departure-gate` with the partner host and subset, and the `VirtualService` `partner-via-gate`), the `DestinationRule` `partner-tls`, and the helper functions `call_partner` and `log_gate` defined in your terminal.

## `MUTUAL` and `credentialName`

With `tls.mode: MUTUAL`, the egress gateway presents a client certificate in the TLS handshake. The field **`credentialName`** names a Kubernetes `Secret` that holds everything the egress gateway needs:

| Key in the `Secret` | What it is |
| --- | --- |
| `tls.crt` | the client certificate the egress gateway presents |
| `tls.key` | the private key that belongs to the client certificate |
| `ca.crt` | the partner's CA certificate, used to verify the partner's server certificate |

The proxy does not read the `Secret` from a file. `istiod` sends it to the proxy over **SDS** (Secret Discovery Service), the part of xDS that carries certificates and keys. xDS is the set of protocols `istiod` uses to push configuration to proxies while they run. Because of this, `istioctl proxy-config secret` shows exactly which certificates a proxy holds.

<!-- astrona:playground:renew -->

The partner has already issued the client certificate, and it is stored in the namespace `starfleet`:

```sh
kubectl get secret partner-client-cert -n starfleet
```

You should see:

```text
NAME                  TYPE     DATA   AGE
partner-client-cert   Opaque   3      2m49s
```

The `Secret` has three keys: `tls.crt`, `tls.key` and `ca.crt`.

Now replace the test settings with `MUTUAL` and the `Secret`'s name. Remove `insecureSkipVerify`, because `ca.crt` now lets the egress gateway verify the partner server. Save this as `destinationrule-partner-tls.yaml`, replacing the earlier version:

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: partner-tls
  namespace: starfleet
spec:
  host: partner.outpost.example
  exportTo:
  - istio-egress
  trafficPolicy:
    portLevelSettings:
    - port:
        number: 443
      tls:
        mode: MUTUAL
        credentialName: partner-client-cert
        sni: partner.outpost.example
```

Apply it:

```sh
kubectl apply -f destinationrule-partner-tls.yaml
```

Then wait about 20 seconds, call the partner server and read the egress gateway's access log:

```sh
sleep 20
call_partner
log_gate
```

You should see (log line shortened):

```text
upstream connect error or disconnect/reset before headers. retried and the latest reset reason: remote connection failure503
"GET / HTTP/2" 503 URX,UF upstream_reset_before_response_started{remote_connection_failure|TLS_error:_Secret_is_not_supplied_by_SDS} ... "partner.outpost.example" "10.96.110.203:443" outbound|443||partner.outpost.example ...
```

`Secret is not supplied by SDS` means the egress gateway has the configuration to present a client certificate, but it never received one. The wait matters. While the egress gateway waits for the certificate, it keeps its old configuration for about 15 seconds, so a call made right away still gets the earlier `400`.

## Where `credentialName` is read from

`credentialName` names a `Secret`, but not its namespace. The proxy that uses it reads it from **its own namespace**. The proxy that needs the certificate here is the egress gateway, in the namespace `istio-egress`. The `Secret` is in `starfleet`.

You can see this from the egress gateway's side. List the certificates it holds:

```sh
istioctl proxy-config secret deploy/istio-egress -n istio-egress
```

You should see:

```text
RESOURCE NAME                               TYPE           STATUS      VALID CERT     SERIAL NUMBER                        NOT AFTER                NOT BEFORE
kubernetes://partner-client-cert                           WARMING     false
kubernetes://partner-client-cert-cacert                    WARMING     false
default                                     Cert Chain     ACTIVE      true           6d21327e4a3e71dea84a0c35eb2cfc63     2026-10-09T23:23:52Z     2026-10-08T23:21:52Z
ROOTCA                                      CA             ACTIVE      true           bd1448216621220aadae74fc4c80395b     2036-10-05T23:23:40Z     2026-10-08T23:23:40Z
file-root:system                            CA             ACTIVE      true           00000000000000005ec3b7a6437fa4e0     2030-12-31T09:37:37Z     2011-05-05T09:37:37Z
```

The two `kubernetes://partner-client-cert` rows are what the egress gateway asked for: one for the client certificate and key, and one (`-cacert`) for the partner's CA. Both are `WARMING`, which means requested but never received. `default` and `ROOTCA` are the egress gateway's own mesh certificate and the mesh CA. `file-root:system` is the list of public CAs that `SIMPLE` used.

`istiod` writes the reason in its own log:

```sh
kubectl logs -n istio-system deploy/istiod | grep partner-client-cert
```

You should see (shortened to the warnings):

```text
2026-10-08T23:31:05.464832Z	warn	ads	failed to fetch key and certificate for kubernetes://partner-client-cert: secret istio-egress/partner-client-cert not found
2026-10-08T23:31:05.464874Z	warn	ads	failed to fetch ca certificate for kubernetes://partner-client-cert-cacert: secret istio-egress/partner-client-cert not found
```

`secret istio-egress/partner-client-cert not found`: `istiod` looked in the egress gateway's namespace. To fix it, copy the three keys out of the `Secret` in `starfleet` into files, then create the same `Secret` in `istio-egress`:

```sh
kubectl get secret partner-client-cert -n starfleet -o jsonpath='{.data.tls\.crt}' | base64 -d > client.crt
kubectl get secret partner-client-cert -n starfleet -o jsonpath='{.data.tls\.key}' | base64 -d > client.key
kubectl get secret partner-client-cert -n starfleet -o jsonpath='{.data.ca\.crt}' | base64 -d > ca.crt
kubectl create secret generic partner-client-cert -n istio-egress \
  --from-file=tls.crt=client.crt --from-file=tls.key=client.key --from-file=ca.crt=ca.crt
```

```text
secret/partner-client-cert created
```

Then call the partner server again:

```sh
call_partner
```

You should see:

```text
client=CN=starfleet-departure-gate verify=SUCCESS
200
```

The partner server received the egress gateway's client certificate (`CN=starfleet-departure-gate`) and accepted it (`verify=SUCCESS`). No restart was needed: `istiod` sent the certificate to the egress gateway as soon as the `Secret` existed.

To see who holds the certificate now, list the certificates of the egress gateway and of the shuttle's sidecar proxy:

```sh
istioctl proxy-config secret deploy/istio-egress -n istio-egress
istioctl proxy-config secret deploy/shuttle -n starfleet
```

You should see:

```text
RESOURCE NAME                               TYPE           STATUS     VALID CERT     SERIAL NUMBER                                NOT AFTER                NOT BEFORE
default                                     Cert Chain     ACTIVE     true           6d21327e4a3e71dea84a0c35eb2cfc63             2026-10-09T23:23:52Z     2026-10-08T23:21:52Z
kubernetes://partner-client-cert            Cert Chain     ACTIVE     true           450764fbaf3caebd2f2ddcacf3e37065538f9f5f     2027-10-08T23:23:54Z     2026-10-08T23:23:54Z
kubernetes://partner-client-cert-cacert     CA             ACTIVE     true           2c3597bcff36e6068b10cc6679239713884838a4     2027-10-08T23:23:54Z     2026-10-08T23:23:54Z
ROOTCA                                      CA             ACTIVE     true           bd1448216621220aadae74fc4c80395b             2036-10-05T23:23:40Z     2026-10-08T23:23:40Z
file-root:system                            CA             ACTIVE     true           00000000000000005ec3b7a6437fa4e0             2030-12-31T09:37:37Z     2011-05-05T09:37:37Z
RESOURCE NAME     TYPE           STATUS     VALID CERT     SERIAL NUMBER                        NOT AFTER                NOT BEFORE
default           Cert Chain     ACTIVE     true           50392ac2318d15be3d01836d7d3023f7     2026-10-09T23:23:55Z     2026-10-08T23:21:55Z
ROOTCA            CA             ACTIVE     true           bd1448216621220aadae74fc4c80395b     2036-10-05T23:23:40Z     2026-10-08T23:23:40Z
```

The egress gateway's partner certificates are now `ACTIVE`. The shuttle holds only its own mesh certificate. The `shuttle` pod can reach the partner server, but it never holds the partner's client certificate. That is the main reason to do the handshake at the egress gateway.

## Egress gateway or sidecar proxy: the trade-off

You could also start TLS in each sidecar proxy, with no egress gateway. Both designs work. This table compares what each one costs:

| | TLS started in each sidecar proxy | TLS started at the egress gateway |
| --- | --- | --- |
| Where the client certificate is stored | the namespace of every calling workload | the egress gateway's namespace only |
| Renewing the certificate | in every namespace that calls the partner | one `Secret` |
| A pod that is broken into | holds the client certificate | holds nothing |
| A new workload that calls the partner | needs its own copy | needs nothing |
| One place to log and check outgoing requests | no, every sidecar proxy | yes, the egress gateway |
| Network hops | direct | one extra |
| Objects per external host | 3 | 5 |
| A component every outgoing request depends on | none | the egress gateway |

The first five rows favour the egress gateway. The last three count against it: an extra hop, more objects, and one egress gateway that every outgoing request depends on. Run it with too few replicas and one failure stops all outgoing traffic. For a public API with no client certificate, TLS in each sidecar proxy is simpler and fine. For a partner that asks for a client certificate, the first row usually decides.

You now know how `MUTUAL` and `credentialName` give the egress gateway a client certificate and a CA, that the `Secret` must be in the egress gateway's own namespace, and how to find a missing one with `istioctl proxy-config secret` and the `istiod` log. You can also weigh where TLS should start. What is left is to use these checks on a route where more than one thing is wrong.

## Common pitfalls

> [!WARNING]
> - **The `Secret` in the caller's namespace.** `credentialName` is read from the namespace of the proxy that uses it: the egress gateway's. The call fails with `503 URX,UF` and `Secret_is_not_supplied_by_SDS`.
> - **Expecting an error when you apply.** `kubectl apply` and `istioctl analyze` accept a `credentialName` that points at nothing. Check `istioctl proxy-config secret` (`WARMING`) and the `istiod` log (`not found`).
> - **Testing right after the change.** The egress gateway keeps its old configuration for about 15 seconds while it waits for the certificate. Wait, then test.
> - **Keeping `insecureSkipVerify: true` next to `MUTUAL`.** The egress gateway then sends its client certificate to any server that answers on that address.

## Your mission: Fix Mutual TLS Origination At The Egress Gateway Lab

You can now give the egress gateway a client certificate with `MUTUAL` and `credentialName`, and find out why a handshake fails from the access log, the egress gateway's certificates and the `istiod` log. In the lab, the partner route is in place, but every request fails, and more than one thing is wrong.

The lab runs in its own cluster, so first pause your playground. Nothing in it is lost:

```sh
astrona stop ats-014-playground-080-02
```

Then start the lab:

```sh
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-080/module-02/labs/lab-02
```

The task is on the next page. Solve it on your own first. When you think you are done, send it for grading:

```sh
astrona submit -c sections/section-080/module-02/labs/lab-02
```

When the lab is done, remove it and start your playground again:

```sh
astrona destroy ats-014-lab-080-02-02
astrona start ats-014-playground-080-02
```
