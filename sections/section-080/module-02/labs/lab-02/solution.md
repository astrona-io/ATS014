# Solution Walkthrough

Two faults, astronaut, and each one hides behind a `503`. Fix the route first, read what the gate says next, then hand it its keys.

---

## Step 1: Read the gate's flight log

Send a test signal, then read the newest line of the gate's flight log. The first answer can take up to 30 seconds:

```sh
kubectl exec -n starfleet deploy/shuttle -- curl -s -w "\n%{http_code}\n" http://partner.outpost.example/
kubectl logs -n istio-egress deploy/istio-egress --tail=1
```

```text
upstream connect error or disconnect/reset before headers. retried and the latest reset reason: connection timeout
503
[2026-10-08T23:42:56.440Z] "GET / HTTP/2" 503 URX,UF upstream_reset_before_response_started{connection_timeout} - "-" 0 114 30036 - "10.244.0.7" "curl/8.11.1" "e17710d6-59ce-43ad-82c2-e645058f63b7" "partner.outpost.example" "10.96.44.169:80" outbound|80||partner.outpost.example - 10.244.0.6:80 10.244.0.7:36430 - -
```

The gate carried the signal, so stage 1 and the `Gateway` work. But the gate sent it on to `10.96.44.169:80`, through the cluster `outbound|80||partner.outpost.example`. The partner only listens on port `443`, so the connection timed out. Stage 2 routes to the wrong port.

---

## Step 2: Send stage 2 to port 443

Stage 2 is the second rule in the `http` list. Change its port to `443`, where the partner listens and where the TLS settings of `partner-tls` apply:

```sh
kubectl patch virtualservice partner-via-gate -n starfleet --type json \
  -p '[{"op":"replace","path":"/spec/http/1/route/0/destination/port/number","value":443}]'
```

```text
virtualservice.networking.istio.io/partner-via-gate patched
```

Send the signal again and read the gate's flight log:

```sh
kubectl exec -n starfleet deploy/shuttle -- curl -s -w "\n%{http_code}\n" http://partner.outpost.example/
kubectl logs -n istio-egress deploy/istio-egress --tail=1
```

```text
upstream connect error or disconnect/reset before headers. retried and the latest reset reason: remote connection failure
503
[2026-10-08T23:43:43.525Z] "GET / HTTP/2" 503 URX,UF upstream_reset_before_response_started{remote_connection_failure|TLS_error:_Secret_is_not_supplied_by_SDS} - "TLS_error:_Secret_is_not_supplied_by_SDS" 0 121 26 - "10.244.0.7" "curl/8.11.1" "751b4206-7e73-44b2-8bea-48704bebede4" "partner.outpost.example" "10.96.44.169:443" outbound|443||partner.outpost.example - 10.244.0.6:80 10.244.0.7:36430 - -
```

Still `503`, but a different one. The gate now calls port `443`, but it cannot start the handshake: `Secret is not supplied by SDS`. It has the order to show a client certificate, and no certificate.

---

## Step 3: Ask the gate which keys it holds

```sh
istioctl proxy-config secret deploy/istio-egress -n istio-egress
```

```text
RESOURCE NAME                               TYPE           STATUS      VALID CERT     SERIAL NUMBER                        NOT AFTER                NOT BEFORE
kubernetes://partner-client-cert                           WARMING     false
kubernetes://partner-client-cert-cacert                    WARMING     false
default                                     Cert Chain     ACTIVE      true           37c3b937105b9439850a6a32ae8c567e     2026-10-09T23:42:27Z     2026-10-08T23:40:27Z
ROOTCA                                      CA             ACTIVE      true           e3f2b11217e069631d06812f1ef1f290     2036-10-05T23:42:15Z     2026-10-08T23:42:15Z
```

Both partner keys are `WARMING`: asked for, never received. Mission control's log says why:

```sh
kubectl logs -n istio-system deploy/istiod | grep partner-client-cert | grep warn
```

```text
2026-10-08T23:42:37.366052Z	warn	ads	failed to fetch key and certificate for kubernetes://partner-client-cert: secret istio-egress/partner-client-cert not found
2026-10-08T23:42:37.366082Z	warn	ads	failed to fetch ca certificate for kubernetes://partner-client-cert-cacert: secret istio-egress/partner-client-cert not found
```

`credentialName` is read from the namespace of the proxy that uses it. That proxy is the gate, so mission control looked in `istio-egress`. The delivered `Secret` is in `starfleet`.

---

## Step 4: Store the keys on the gate's planet

Copy the three keys out of the delivered `Secret`, and create the same `Secret` in `istio-egress`:

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

No restart is needed. Mission control sends the keys to the gate as soon as the `Secret` exists.

---

## Step 5: Prove it

Send the signal, read the gate's flight log, and list the gate's keys:

```sh
kubectl exec -n starfleet deploy/shuttle -- curl -s -w "\n%{http_code}\n" http://partner.outpost.example/
kubectl logs -n istio-egress deploy/istio-egress --tail=1
istioctl proxy-config secret deploy/istio-egress -n istio-egress
```

```text
client=CN=starfleet-departure-gate verify=SUCCESS

200
[2026-10-08T23:43:59.912Z] "GET / HTTP/2" 200 - via_upstream - "-" 0 50 5 5 "10.244.0.7" "curl/8.11.1" "51fe6a26-2cf2-4e05-8f33-b6d6f4c6bed2" "partner.outpost.example" "10.96.44.169:443" outbound|443||partner.outpost.example 10.244.0.6:43274 10.244.0.6:80 10.244.0.7:36430 - -
RESOURCE NAME                               TYPE           STATUS     VALID CERT     SERIAL NUMBER                                NOT AFTER                NOT BEFORE
default                                     Cert Chain     ACTIVE     true           37c3b937105b9439850a6a32ae8c567e             2026-10-09T23:42:27Z     2026-10-08T23:40:27Z
kubernetes://partner-client-cert            Cert Chain     ACTIVE     true           4851c9ee6af561ec79d1eee6a593bc3d5c2acbd9     2027-10-08T23:42:29Z     2026-10-08T23:42:29Z
kubernetes://partner-client-cert-cacert     CA             ACTIVE     true           3365a8a34694a93586084bec53b2a81069b7a628     2027-10-08T23:42:29Z     2026-10-08T23:42:29Z
ROOTCA                                      CA             ACTIVE     true           e3f2b11217e069631d06812f1ef1f290             2036-10-05T23:42:15Z     2026-10-08T23:42:15Z
```

The partner accepted the gate's certificate (`verify=SUCCESS`), the gate's line ends at port `443`, and both keys are `ACTIVE`. Last, check that the shuttle's sidecar holds no TLS settings for the partner:

```sh
istioctl proxy-config cluster deploy/shuttle -n starfleet --fqdn partner.outpost.example -o json | grep -c transportSocket
```

```text
0
```

Only the gate starts the TLS connection, and only the gate holds the keys.

---

## Common Mistakes

- **Fixing only one fault.** Each fault gives its own `503`. After the port fix, the flight log changes from `connection_timeout` to `Secret_is_not_supplied_by_SDS`: read it again after every change.
- **Leaving the `Secret` in `starfleet`, or changing `credentialName`.** `credentialName` has no namespace. The gate reads it from `istio-egress`.
- **Switching to `SIMPLE` or adding `insecureSkipVerify: true`.** The partner asks for a client certificate, and the grader expects `partner-tls` unchanged.
- **Removing `exportTo`.** The shuttle's sidecar then gets the TLS settings too, and the grader checks that it has none.
- **Creating the `Secret` without `ca.crt`.** The task asks for all three keys: the gate needs the partner's authority to check the partner.
- **Testing right after a change.** Mission control needs a few seconds to send new orders. If the answer looks old, send the signal again.
