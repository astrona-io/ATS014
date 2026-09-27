# Solution Walkthrough

Three objects that only work together. The endpoint reports the scheme it was reached over, so there is no ambiguity about whether you succeeded.

---

## Step 1: Understand What You Are Up Against

```sh
SECURE=$(cat /tmp/secure-ip); echo "endpoint: $SECURE"
kubectl -n outside-mesh get pod secure-api -o wide

# plaintext to the TLS port - fails, as it must
kubectl -n tlsorig-demo exec deploy/tester -- \
  curl -s -o /dev/null -w 'plain to 8443: %{http_code}\n' --max-time 10 "http://$SECURE:8443/"

# TLS directly - works, but the mesh learns nothing from it
kubectl -n tlsorig-demo exec deploy/tester -- \
  curl -sk --max-time 10 "https://$SECURE:8443/"
kubectl -n tlsorig-demo logs deploy/tester -c istio-proxy --tail=1
```

```text
endpoint: 10.244.0.16
NAME         READY   STATUS    IP
secure-api   1/1     Running   10.244.0.16
plain to 8443: 000
scheme=https
[2026-09-27T12:31:05.442Z] "- - -" 0 - - - "-" 705 5923 212 - "-" "-" "-" "-" "10.244.0.16:8443" ...
```

Three facts established. The endpoint refuses plaintext. It answers `scheme=https` when reached properly. And when the *application* does the TLS, the proxy's log line is `"- - -"` — no method, no path, no status. That last line is the problem this module solves.

---

## Step 2: Register the Host With Both Ports

```sh
SECURE=$(cat /tmp/secure-ip)
kubectl apply -f - <<EOF
apiVersion: networking.istio.io/v1
kind: ServiceEntry
metadata:
  name: secure-api
  namespace: tlsorig-demo
spec:
  hosts:
    - secure.example.com
  addresses:
    - $SECURE
  ports:
    - number: 8080
      name: http
      protocol: HTTP
    - number: 8443
      name: https
      protocol: HTTPS
  location: MESH_EXTERNAL
  resolution: STATIC
  endpoints:
    - address: $SECURE
EOF
```

**Both ports.** 8080 declared `HTTP` is where the application's plaintext request arrives and the reason the proxy can read it; 8443 declared `HTTPS` is where the traffic is going. Declaring only 8443 is the most common first attempt and leaves the redirect in the next step with nothing to match.

Note the unquoted heredoc so `$SECURE` is substituted.

---

## Step 3: Redirect the Port

```sh
kubectl apply -f - <<'EOF'
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: secure-api
  namespace: tlsorig-demo
spec:
  hosts:
    - secure.example.com
  http:
    - match:
        - port: 8080
      route:
        - destination:
            host: secure.example.com
            port:
              number: 8443
EOF
```

Ordinary routing with the ports doing the work. The **host is unchanged** — only the port moves.

Test now, before the third object, to see the intermediate failure:

```sh
SECURE=$(cat /tmp/secure-ip)
kubectl -n tlsorig-demo exec deploy/tester -- \
  curl -s -o /dev/null -w 'without DestinationRule: %{http_code}\n' --max-time 15 "http://$SECURE:8080/"
```

```text
without DestinationRule: 503
```

The traffic now reaches port 8443 — as plaintext, which the endpoint drops. Each object has a distinct failure, and this is the one for a missing `DestinationRule`.

---

## Step 4: Originate the TLS

```sh
kubectl apply -f - <<'EOF'
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: secure-api
  namespace: tlsorig-demo
spec:
  host: secure.example.com
  trafficPolicy:
    portLevelSettings:
      - port:
          number: 8443
        tls:
          mode: SIMPLE
          sni: secure.example.com
          insecureSkipVerify: true
EOF
```

Three details:

- **`portLevelSettings` for 8443, not the top of `trafficPolicy`.** A top-level `tls` applies to port 8080 as well, so the proxy would try to originate TLS on the plaintext side too and the arrangement collapses — with a 503 and an object that looks fine.
- **`sni: secure.example.com`.** The proxy is the TLS client now and must announce the server name. This endpoint's certificate carries that name.
- **`insecureSkipVerify: true`** because the certificate is self-signed and nothing in the proxy's trust store issued it. In production you supply `caCertificates` instead; here it is a deliberate lab shortcut, and the grader expects it.

---

## Step 5: The Decisive Test

```sh
SECURE=$(cat /tmp/secure-ip)
kubectl -n tlsorig-demo exec deploy/tester -- \
  curl -s -w '\nstatus: %{http_code}\n' --max-time 15 "http://$SECURE:8080/"
```

```text
scheme=https
status: 200
```

An `http://` call, a `200`, and the endpoint reporting **`scheme=https`**. The endpoint speaks only TLS, so it could not have answered at all unless the sidecar did the handshake. The application never changed.

---

## Step 6: Confirm the Visibility Came Back

```sh
kubectl -n tlsorig-demo logs deploy/tester -c istio-proxy --tail=1
istioctl proxy-config cluster deploy/tester -n tlsorig-demo --fqdn secure.example.com -o json \
  | grep -A3 transportSocket | head -5
```

```text
[2026-09-27T12:44:18.907Z] "GET / HTTP/1.1" 200 - via_upstream - "-" 0 14 3 2 "-" "curl/8.5.0" ... "secure.example.com:8443"
"transportSocket": {
  "name": "envoy.transport_sockets.tls",
```

Compare that log line with step 1's. A method, a path and a status where there were dashes — which means every layer-7 feature in this course now applies to this call. The `transportSocket` on the cluster is the proxy-side confirmation.

Try adding a `timeout` to the `VirtualService` if you want to see that claim demonstrated.

---

## Common Mistakes

- **Declaring only port 8443.** The plaintext request has nowhere to arrive; the redirect matches nothing.
- **`tls` at the top of `trafficPolicy`.** It applies to 8080 as well and breaks the plaintext side — a 503 from an object that looks correct.
- **Omitting `sni`.** This endpoint's certificate names `secure.example.com`; without SNI the handshake has nothing to select on.
- **Omitting `insecureSkipVerify`.** The certificate is self-signed, so verification fails and the handshake is rejected.
- **Omitting the `VirtualService`.** Traffic stays on 8080, the endpoint never sees a TLS handshake.
- **Pointing the `VirtualService` at the IP instead of the host.** It must name the `ServiceEntry` host.
- **Calling `https://` from the client.** Then the sidecar sees an encrypted stream and none of this applies.
- **Creating a Service in `outside-mesh`.** That puts the endpoint in the registry through the back door.
