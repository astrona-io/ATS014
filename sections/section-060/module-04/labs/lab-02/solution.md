# Solution Walkthrough

Both hosts fail for a reason that no object reports. The first host fails because its certificate is in a namespace that the gateway never reads. The second host fails because its route is the wrong kind for a server that does not decrypt. The Start section shows both symptoms. Items 1 and 2 fix the first host, items 3 and 4 fix the second, and items 5 and 6 are what you must not change.

---

## Start: Confirm The Failures And Find The Causes

Start the port forward from the task, then send one request for each host:

```sh
curl -sk -o /dev/null -w 'starfleet: %{http_code}\n' --resolve starfleet.example.com:8443:127.0.0.1 https://starfleet.example.com:8443/anything/dock
curl -sk -o /dev/null -w 'archive: %{http_code}\n' --resolve archive.starfleet.example.com:8443:127.0.0.1 https://archive.starfleet.example.com:8443/
```

The first request prints `000`: the TLS handshake does not finish. The archive request does not return the archive's body either. Start with the first host. Ask the gateway proxy for its secrets, and find where the secret is:

```sh
istioctl proxy-config secret deploy/istio-ingressgateway -n istio-system
kubectl get secret -A | grep starfleet-tls
```

The secret `kubernetes://starfleet-tls` has the status `WARMING`: the gateway asked for it and has no certificate. The second command shows that the secret `starfleet-tls` exists, but in the namespace `starfleet`. The gateway pod runs in `istio-system` and reads secrets only from there. That is the first cause.

For the second host, read the `Gateway` and the `VirtualService`:

```sh
kubectl get gateway starfleet-gateway -n starfleet -o yaml
kubectl get virtualservice archive -n starfleet -o yaml
```

The server for `archive.starfleet.example.com` has `tls.mode: PASSTHROUGH`. That means the gateway forwards the encrypted bytes and never decrypts them, so it cannot read a path or a header. The `VirtualService` `archive` uses an `http:` rule, which needs a decrypted HTTP request. That is the second cause.

---

## Task items 1 And 2: The Certificate For starfleet.example.com

> **Task item 1:** `GET /anything/dock` over **HTTPS** on port 8443, with the name `starfleet.example.com` as SNI, returns **200**.

> **Task item 2:** The certificate that the gateway serves for `starfleet.example.com` is the one from `/tmp/starfleet-example.crt`, and the gateway proxy holds `kubernetes://starfleet-tls` with the status `ACTIVE`.

These two items share one fix. Create the secret in `istio-system` from the same files, and remove the unused copy:

```sh
kubectl -n istio-system create secret tls starfleet-tls \
  --key=/tmp/starfleet-example.key --cert=/tmp/starfleet-example.crt
kubectl -n starfleet delete secret starfleet-tls
```

Check item 2 first, then item 1. The secret `kubernetes://starfleet-tls` is now `ACTIVE`. The fingerprint that the gateway sends is the fingerprint of your file:

```sh
istioctl proxy-config secret deploy/istio-ingressgateway -n istio-system
openssl s_client -connect 127.0.0.1:8443 -servername starfleet.example.com </dev/null 2>/dev/null | openssl x509 -noout -fingerprint -sha256
openssl x509 -in /tmp/starfleet-example.crt -noout -fingerprint -sha256
curl -sk -o /dev/null -w '%{http_code}\n' --resolve starfleet.example.com:8443:127.0.0.1 https://starfleet.example.com:8443/anything/dock
```

The two fingerprints are the same, and the request returns `200`. Wait a few seconds after you create the secret: `istiod` needs a moment to send it to the gateway.

---

## Task items 3 And 4: The Passthrough Host

> **Task item 3:** A request over HTTPS on port 8443 with the name `archive.starfleet.example.com` as SNI reaches the `archive` and returns its body, `{"service":"archive"}`.

> **Task item 4:** The certificate presented for `archive.starfleet.example.com` is the `archive`'s own certificate, the one in the secret `archive-tls` in `starfleet`. The gateway must not decrypt this traffic.

These two items share one fix: replace the `http:` rule with a `tls:` match on the SNI. Do not change the `Gateway`: its `PASSTHROUGH` server is correct, and a `SIMPLE` server would make the gateway present a certificate of its own. Save this as `virtualservice-archive.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: archive
  namespace: starfleet
spec:
  hosts:
  - archive.starfleet.example.com
  gateways:
  - starfleet-gateway
  tls:
  - match:
    - port: 443
      sniHosts:
      - archive.starfleet.example.com
    route:
    - destination:
        host: archive
        port:
          number: 443
```

Apply it:

```sh
kubectl apply -f virtualservice-archive.yaml
```

Check both items. The body is `{"service":"archive"}`, and the fingerprint that the gateway sends is the fingerprint of the certificate in the secret `archive-tls`:

```sh
curl -sk --resolve archive.starfleet.example.com:8443:127.0.0.1 https://archive.starfleet.example.com:8443/
openssl s_client -connect 127.0.0.1:8443 -servername archive.starfleet.example.com </dev/null 2>/dev/null | openssl x509 -noout -fingerprint -sha256
kubectl -n starfleet get secret archive-tls -o go-template='{{index .data "tls.crt" | base64decode}}' | openssl x509 -noout -fingerprint -sha256
```

The two fingerprints are the same. The `archive` pod terminated TLS, and the gateway only forwarded the bytes.

---

## Task items 5 And 6: What Must Stay The Same

> **Task item 5:** The `Gateway` keeps its two servers: ...

> **Task item 6:** The Deployments and Services in `starfleet` stay unchanged.

You did not edit the `Gateway`, a Deployment or a Service, so both items hold. Check the `Gateway` modes once more:

```sh
kubectl get gateway starfleet-gateway -n starfleet -o jsonpath='{range .spec.servers[*]}{.hosts[0]} {.port.protocol} {.tls.mode}{"\n"}{end}'
```

The first line shows `HTTPS` and `SIMPLE`, and the second shows `TLS` and `PASSTHROUGH`.

---

## Submit

```sh
astrona submit -c sections/section-060/module-04/labs/lab-02
```

## Mistakes That Fail The Grader

- **Items 1 and 2:** the secret stays in `starfleet`, or its name differs from `credentialName`. The gateway reads `istio-system` only, and the secret stays `WARMING`.
- **Items 1 and 2:** a new certificate is created instead of the one in `/tmp/starfleet-example.crt`.
- **Items 3 and 4:** the `http:` rule stays, or a `tls:` match names a different host in `sniHosts`.
- **Items 4 and 5:** the `archive` server is changed to `SIMPLE` with a certificate in `istio-system`. The gateway then presents its own certificate, not the archive's.
- **Item 6:** the `archive` Deployment is changed (for example a sidecar proxy is added), or a Service is replaced.
