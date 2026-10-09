# Hand The Gate Its Keys

The partner checks IDs in both directions, so the gate needs two things: the partner's authority, to check the partner, and a client certificate, to show its own ID. In this part you give the gate both with `tls.mode: MUTUAL` and one field, `credentialName`. Then you find out which planet the keys must be stored on.

The commands below need the four partner routing objects (`ServiceEntry` `partner`, the `Gateway` and `DestinationRule` `departure-gate` with the partner host and subset, and the `VirtualService` `partner-via-gate`), the `DestinationRule` `partner-tls`, and the helpers from the landing page in your playground.

## `MUTUAL` and `credentialName`

With `tls.mode: MUTUAL`, the gate shows a client certificate in the handshake. The field **`credentialName`** names a Kubernetes `Secret` that holds everything the gate needs:

| Key in the `Secret` | What it is |
| --- | --- |
| `tls.crt` | the client certificate: the gate's ID card |
| `tls.key` | the private key that proves the ID card belongs to the gate |
| `ca.crt` | the partner's certificate authority, used to check the partner's ID |

The proxy does not read the `Secret` from a file. Mission control sends it over **SDS** (Secret Discovery Service). SDS is the part of the xDS (discovery service) orders that carries certificates and keys. So `istioctl proxy-config secret` shows you exactly which keys a proxy holds.

<!-- astrona:playground:renew -->

### Look at the keys you were given

The partner's security officer has already delivered the client certificate. It landed on your own planet, `starfleet`:

```sh
kubectl get secret partner-client-cert -n starfleet
```

You should see:

```text
NAME                  TYPE     DATA   AGE
partner-client-cert   Opaque   3      2m49s
```

Three keys: `tls.crt`, `tls.key` and `ca.crt`.

### Switch the lock to `MUTUAL`

Replace the test settings with `MUTUAL` and the `Secret`'s name. `insecureSkipVerify` goes away, because `ca.crt` now lets the gate check the partner. Save this as `destinationrule-partner-tls.yaml`, replacing the earlier version:

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

Then wait about 20 seconds, call the partner and read the gate's flight log:

```sh
sleep 20
call_partner
log_gate
```

You should see (the log line trimmed):

```text
upstream connect error or disconnect/reset before headers. retried and the latest reset reason: remote connection failure503
"GET / HTTP/2" 503 URX,UF upstream_reset_before_response_started{remote_connection_failure|TLS_error:_Secret_is_not_supplied_by_SDS} ... "partner.outpost.example" "10.96.110.203:443" outbound|443||partner.outpost.example ...
```

`Secret is not supplied by SDS`: the gate has the order to show a client certificate, but it never received one. The wait matters. While the gate waits for the keys, it keeps its old orders for about 15 seconds, so a call made right away still gets the earlier `400`.

## Where `credentialName` is read from

`credentialName` names a `Secret`, but not its namespace. The proxy that loads it reads it from **its own namespace**. A ship can only open the safe on its own planet, and the ship that needs the keys here is the gate, on the planet `istio-egress`. The `Secret` is on `starfleet`.

### Ask the gate which keys it holds

List the gate's keys:

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

The two `kubernetes://partner-client-cert` rows are the keys the gate asked for, one for the ID card and one (`-cacert`) for the partner's authority. Both are `WARMING`: asked for, never received. `default` and `ROOTCA` are the gate's own mesh ID, and `file-root:system` is the public authority list that `SIMPLE` used.

Mission control says why, in its own log:

```sh
kubectl logs -n istio-system deploy/istiod | grep partner-client-cert
```

You should see (trimmed to the warnings):

```text
2026-10-08T23:31:05.464832Z	warn	ads	failed to fetch key and certificate for kubernetes://partner-client-cert: secret istio-egress/partner-client-cert not found
2026-10-08T23:31:05.464874Z	warn	ads	failed to fetch ca certificate for kubernetes://partner-client-cert-cacert: secret istio-egress/partner-client-cert not found
```

`secret istio-egress/partner-client-cert not found`. Mission control looked on the gate's planet.

### Store the keys on the gate's planet

Copy the three keys out of the `Secret` on `starfleet` into files, then create the same `Secret` on `istio-egress`:

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

Then call the partner again:

```sh
call_partner
```

You should see:

```text
client=CN=starfleet-departure-gate verify=SUCCESS
200
```

The partner saw the gate's ID card (`CN=starfleet-departure-gate`) and accepted it (`verify=SUCCESS`). No restart was needed: mission control sent the keys to the gate as soon as the `Secret` existed.

### Check who holds the keys

List the keys of the gate and of the shuttle's sidecar:

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

The gate's partner keys are now `ACTIVE`. The shuttle holds only its own mesh ID. Your ship can reach the partner, but it never touches the partner's keys. That is the whole reason to put the handshake at the gate.

## Gate or sidecar: the trade-off

You could also put the lock on in each sidecar, with no gate. Both ways work. This table shows what each one costs:

| | Lock put on in each sidecar | Lock put on at the gate |
| --- | --- | --- |
| Where the client certificate is stored | the namespace of every calling ship | the gate's namespace only |
| Renewing the certificate | on every planet that calls the partner | one `Secret` |
| A ship that is broken into | holds the client certificate | holds nothing |
| A new ship that calls the partner | needs its own copy | needs nothing |
| One place to log and check outgoing signals | no, every sidecar | yes, the gate |
| Network hops | direct | one extra |
| Objects per outside host | 3 | 5 |
| A component every signal depends on | none | the gate |

The first five rows are the case for the gate. The last three are the case against it: an extra hop, more objects, and one gate that every outgoing signal depends on. Run that gate with too few copies and it becomes your Death Star: huge, powerful, and one weak spot takes all outgoing traffic down. For a public API with no client certificate, the lock in each sidecar is simpler and fine. For a partner that checks IDs, the first row usually decides it.

## Common pitfalls

> [!WARNING]
> - **The `Secret` in the caller's namespace.** `credentialName` is read from the namespace of the proxy that uses it: the gate's. The call fails with `503 URX,UF` and `Secret_is_not_supplied_by_SDS`.
> - **Expecting an error when you apply.** `kubectl apply` and `istioctl analyze` accept a `credentialName` that points at nothing. Look at `istioctl proxy-config secret` (`WARMING`) and the `istiod` log (`not found`).
> - **Testing right after the change.** The gate keeps its old orders for about 15 seconds while it waits for keys. Wait, then test.
> - **Keeping `insecureSkipVerify: true` next to `MUTUAL`.** Your gate shows its ID card to anyone who answers on that address.

> *The keys live with the proxy that uses them. At the gate, that is one `Secret` on the gate's planet, and none on your ships.*

## Your mission: Open The Partner's Locked Door

You can now give the gate its keys with `MUTUAL` and `credentialName`, and find out why a handshake fails from the flight log, the gate's keys and mission control's log. Now prove it in a graded mission: the partner route is in place, but signals still bounce off a locked door, and more than one thing is wrong.

The mission runs in its own training solar system, so first pause your playground. Nothing in it is lost:

```sh
astrona stop ats-014-playground-080-02
```

Then start the mission:

```sh
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-080/module-02/labs/lab-02
```

Read the task in [`question.md`](./labs/lab-02/question.md) and solve it on your own first. When you think you are done, send it for grading:

```sh
astrona submit -c sections/section-080/module-02/labs/lab-02
```

When the mission is done, remove it and wake your playground up again:

```sh
astrona destroy ats-014-lab-080-02-02
astrona start ats-014-playground-080-02
```
