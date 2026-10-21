# Solution Walkthrough

The walkthrough follows the task. The setup has two faults, and each one gives a `503` with its own message in the egress gateway access log. Fix the route first, then read the next message. Items 1 and 2 are the result of both fixes, so the walkthrough proves them after items 3 and 4. Item 5 checks the sidecar proxy of `shuttle`.

The outputs below come from a real run. Your addresses, timestamps and UIDs differ. The first request can take up to 30 seconds.

---

## Start: Look At The Symptom

List the five objects, and print the two routing rules and the TLS rule. Save the identity of what must not change:

```sh
kubectl -n starfleet get serviceentry,gateway,destinationrule,virtualservice
kubectl -n starfleet get virtualservice partner-via-gate -o jsonpath='{range .spec.http[*]}{.match}{" -> "}{.route[0].destination.host}{":"}{.route[0].destination.port.number}{"\n"}{end}'
kubectl -n starfleet get destinationrule partner-tls -o jsonpath='gen={.metadata.generation} {.spec}{"\n"}'
kubectl -n starfleet get secret
kubectl -n istio-egress get secret
kubectl -n outpost get pods -o custom-columns=NAME:.metadata.name,UID:.metadata.uid
```

```text
NAME                                       HOSTS                         LOCATION        RESOLUTION   AGE
serviceentry.networking.istio.io/partner   ["partner.outpost.example"]   MESH_EXTERNAL   DNS          10s

NAME                                         AGE
gateway.networking.istio.io/departure-gate   10s

NAME                                                 HOST                                          AGE
destinationrule.networking.istio.io/departure-gate   istio-egress.istio-egress.svc.cluster.local   10s
destinationrule.networking.istio.io/partner-tls      partner.outpost.example                       10s

NAME                                                  GATEWAYS                    HOSTS                         AGE
virtualservice.networking.istio.io/partner-via-gate   ["mesh","departure-gate"]   ["partner.outpost.example"]   10s
[{"gateways":["mesh"],"port":80}] -> istio-egress.istio-egress.svc.cluster.local:80
[{"gateways":["departure-gate"],"port":80}] -> partner.outpost.example:80
gen=1 {"exportTo":["istio-egress"],"host":"partner.outpost.example","trafficPolicy":{"portLevelSettings":[{"port":{"number":443},"tls":{"credentialName":"partner-client-cert","mode":"MUTUAL","sni":"partner.outpost.example"}}]}}
NAME                 TYPE     DATA   AGE
partner-client-cert  Opaque   3      17s
NAME                                 TYPE                 DATA   AGE
sh.helm.release.v1.istio-egress.v1   helm.sh/release.v1   1      26s
NAME                      UID
partner-6499b5b9f-lt9bk   aec01ea2-21e7-4ea3-99b8-c0f461f0f700
```

Rule 2 sends to port `80`, and the `Secret` exists only in `starfleet`. Keep the `partner-tls` generation (`gen=1`) and the partner pod UID: both must be the same at the end.

Now send the test request, wait for the log, and read the last line of the egress gateway access log (cut to 330 characters):

```sh
kubectl exec -n starfleet deploy/shuttle -- curl -s -w "\n%{http_code}\n" http://partner.outpost.example/
sleep 3
kubectl logs -n istio-egress deploy/istio-egress --tail=1 | cut -c1-330
```

```text
upstream connect error or disconnect/reset before headers. retried and the latest reset reason: connection timeout
503
[2026-10-20T22:32:58.966Z] "GET / HTTP/2" 503 URX,UF upstream_reset_before_response_started{connection_timeout} - "-" 0 114 30043 - "10.244.0.7" "curl/8.11.1" "fb10223f-eda4-4d09-b6d0-5f9e58b61675" "partner.outpost.example" "10.96.248.10:80" outbound|80||partner.outpost.example - 10.244.0.6:80 10.244.0.7:36430 - -
```

The egress gateway received the request, so rule 1 and the `Gateway` work. The gateway then called `10.96.248.10:80` (cluster `outbound|80||partner.outpost.example`), and the connection timed out after about 30 seconds. The partner only listens on `443`.

---

## Item 3: Route Rule 2 To Port 443

> **Task item 3:** The second rule of `partner-via-gate` (the rule for the `departure-gate` gateway) routes to `partner.outpost.example` on port `443`. The first rule still matches `mesh` and routes to the egress gateway's Service.

Rule 2 is the second entry of the `http` list. Change its port to `443`, which is also the port where the TLS settings of `partner-tls` apply:

```sh
kubectl patch virtualservice partner-via-gate -n starfleet --type json \
  -p '[{"op":"replace","path":"/spec/http/1/route/0/destination/port/number","value":443}]'
```

```text
virtualservice.networking.istio.io/partner-via-gate patched
```

Check the two rules:

```sh
kubectl -n starfleet get virtualservice partner-via-gate -o jsonpath='{range .spec.http[*]}{.match}{" -> "}{.route[0].destination.host}{":"}{.route[0].destination.port.number}{"\n"}{end}'
```

```text
[{"gateways":["mesh"],"port":80}] -> istio-egress.istio-egress.svc.cluster.local:80
[{"gateways":["departure-gate"],"port":80}] -> partner.outpost.example:443
```

Rule 1 is unchanged. Only the destination port of rule 2 changed. The match port `80` of rule 2 is the port of the `Gateway` listener, so it stays.

---

## Item 4: Give The Egress Gateway The Certificate

> **Task item 4:** The egress gateway has loaded `kubernetes://partner-client-cert` (status `ACTIVE` in `istioctl proxy-config secret`), from a `Secret` with `tls.crt`, `tls.key` and `ca.crt`.

Send the request again and read the access log. This is the second fault:

```sh
kubectl exec -n starfleet deploy/shuttle -- curl -s -w "\n%{http_code}\n" http://partner.outpost.example/
sleep 3
kubectl logs -n istio-egress deploy/istio-egress --tail=1 | cut -c1-330
```

```text
upstream connect error or disconnect/reset before headers. retried and the latest reset reason: remote connection failure
503
[2026-10-20T22:33:40.313Z] "GET / HTTP/2" 503 URX,UF upstream_reset_before_response_started{remote_connection_failure|TLS_error:_Secret_is_not_supplied_by_SDS} - "TLS_error:_Secret_is_not_supplied_by_SDS" 0 121 45 - "10.244.0.7" "curl/8.11.1" "249d0fd0-53ef-4e44-b185-efa9091fc687" "partner.outpost.example" "10.96.248.10:443" out
```

The gateway now calls port `443`, but it cannot start the handshake: `Secret is not supplied by SDS`. SDS (Secret Discovery Service) is how `istiod` sends certificates to a proxy. List the certificates of the egress gateway, and read the `istiod` warnings:

```sh
istioctl proxy-config secret deploy/istio-egress -n istio-egress
kubectl logs -n istio-system deploy/istiod | grep partner-client-cert | grep warn | tail -2 | cut -c1-220
```

```text
RESOURCE NAME                               TYPE           STATUS      VALID CERT     SERIAL NUMBER                        NOT AFTER                NOT BEFORE
kubernetes://partner-client-cert                           WARMING     false
kubernetes://partner-client-cert-cacert                    WARMING     false
default                                     Cert Chain     ACTIVE      true           aac6365b8f5a7cbd400bdd2ca8daf837     2026-10-21T22:32:38Z     2026-10-20T22:30:38Z
ROOTCA                                      CA             ACTIVE      true           6b2abd54c3db1108309e7e983fe90185     2036-10-17T22:32:27Z     2026-10-20T22:32:27Z
2026-10-20T22:32:48.219341Z	warn	ads	failed to fetch key and certificate for kubernetes://partner-client-cert: secret istio-egress/partner-client-cert not found
2026-10-20T22:32:48.219362Z	warn	ads	failed to fetch ca certificate for kubernetes://partner-client-cert-cacert: secret istio-egress/partner-client-cert not found
```

Both partner entries are `WARMING`: the gateway asked for them and never got them. `credentialName` is read from the namespace of the proxy that uses it. That proxy is the egress gateway, so `istiod` looked in `istio-egress`. The delivered `Secret` is in `starfleet`.

Copy the three keys of the delivered `Secret` and create the same `Secret` in `istio-egress`:

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

No restart is needed. `istiod` sends the certificate to the egress gateway as soon as the `Secret` exists. Check the certificates again:

```sh
sleep 8
istioctl proxy-config secret deploy/istio-egress -n istio-egress
```

```text
RESOURCE NAME                               TYPE           STATUS     VALID CERT     SERIAL NUMBER                                NOT AFTER                NOT BEFORE
default                                     Cert Chain     ACTIVE     true           aac6365b8f5a7cbd400bdd2ca8daf837             2026-10-21T22:32:38Z     2026-10-20T22:30:38Z
kubernetes://partner-client-cert            Cert Chain     ACTIVE     true           592736a6624a6a84d122641149af39aa2975f440     2027-10-20T22:58:09Z     2026-10-20T22:58:09Z
ROOTCA                                      CA             ACTIVE     true           6b2abd54c3db1108309e7e983fe90185             2036-10-17T22:32:27Z     2026-10-20T22:32:27Z
kubernetes://partner-client-cert-cacert     CA             ACTIVE     true           404e19c5552b3ba8e9d6d7a0a4f1c7fd22f5e45      2027-10-20T22:58:09Z     2026-10-20T22:58:09Z
```

Both partner entries are `ACTIVE`, with a valid certificate.

---

## Items 1 And 2: Prove The Request Works

> **Task item 1:** `GET http://partner.outpost.example/` from `deploy/shuttle` in `starfleet` returns `200`, and the partner server reports `verify=SUCCESS` for the client certificate `CN=starfleet-departure-gate`.
>
> **Task item 2:** The egress gateway's own access log gains a line for that request, with an upstream on port `443`.

Both items are the result of items 3 and 4. Send the request and read the access log:

```sh
kubectl exec -n starfleet deploy/shuttle -- curl -s -w "\n%{http_code}\n" http://partner.outpost.example/
sleep 3
kubectl logs -n istio-egress deploy/istio-egress --tail=1 | cut -c1-330
```

```text
client=CN=starfleet-departure-gate verify=SUCCESS

200
[2026-10-20T23:23:53.281Z] "GET / HTTP/2" 200 - via_upstream - "-" 0 50 4 3 "10.244.0.7" "curl/8.11.1" "caef8ab7-db8f-4c60-86c4-d4c9b429e36e" "partner.outpost.example" "10.96.248.10:443" outbound|443||partner.outpost.example 10.244.0.6:53270 10.244.0.6:80 10.244.0.7:56146 - -
```

The partner accepted the certificate of the egress gateway (`verify=SUCCESS`). The access log line of the egress gateway shows the upstream `10.96.248.10:443`. The sidecar proxy of `shuttle` sent plain HTTP, and the gateway started the mutual TLS connection.

---

## Item 5: Check That The Sidecar Proxy Has No TLS Settings

> **Task item 5:** The shuttle's sidecar proxy has no TLS settings and no certificate for the partner.

Count the `transportSocket` entries, the TLS settings of an Envoy cluster, in the `shuttle` cluster for the partner:

```sh
istioctl proxy-config cluster deploy/shuttle -n starfleet --fqdn partner.outpost.example -o json | grep -c transportSocket
```

```text
0
```

`partner-tls` has `exportTo: [istio-egress]`, so only the egress gateway gets the TLS settings. Confirm that the rest did not change:

```sh
kubectl -n starfleet get destinationrule partner-tls -o jsonpath='gen={.metadata.generation} {.spec}{"\n"}'
kubectl -n starfleet get virtualservice,gateway
kubectl -n outpost get pods -o custom-columns=NAME:.metadata.name,UID:.metadata.uid
```

```text
gen=1 {"exportTo":["istio-egress"],"host":"partner.outpost.example","trafficPolicy":{"portLevelSettings":[{"port":{"number":443},"tls":{"credentialName":"partner-client-cert","mode":"MUTUAL","sni":"partner.outpost.example"}}]}}
NAME                                                  GATEWAYS                    HOSTS                         AGE
virtualservice.networking.istio.io/partner-via-gate   ["mesh","departure-gate"]   ["partner.outpost.example"]   67s

NAME                                         AGE
gateway.networking.istio.io/departure-gate   67s
NAME                      UID
partner-6499b5b9f-lt9bk   aec01ea2-21e7-4ea3-99b8-c0f461f0f700
```

`partner-tls` is still generation 1 and has no `insecureSkipVerify`. There is still one `VirtualService` and one `Gateway`, and the partner pod has the same UID.

---

## Submit

Send the setup for grading:

```sh
astrona submit -c sections/section-080/module-02/labs/lab-02
```

---

## Mistakes That Fail The Grader

- **Fixing only one fault (items 1 and 2).** Each fault gives its own `503`. After the port fix, the access log changes from `connection_timeout` to `Secret_is_not_supplied_by_SDS`, so read it again after every change.
- **Leaving the `Secret` in `starfleet`, or changing `credentialName` (item 4).** `credentialName` has no namespace. The egress gateway reads it from `istio-egress`.
- **Creating the `Secret` without `ca.crt` (item 4).** The egress gateway needs the certificate authority to verify the partner server.
- **Switching to `SIMPLE` or adding `insecureSkipVerify: true` (items 1 and 4).** The partner asks for a client certificate, and the task says to keep `partner-tls` unchanged.
- **Removing `exportTo` (item 5).** The sidecar proxy of `shuttle` then gets the TLS settings and the grader finds a `transportSocket`.
- **Changing the match port of rule 2, or the first rule (item 3).** Only the destination port of rule 2 is wrong.
- **Adding a second `VirtualService` or `Gateway`.** Edit the existing objects.
- **Testing right after a change.** `istiod` needs a few seconds to send new configuration. If the response looks old, send the request again.
