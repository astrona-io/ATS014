# Solution Walkthrough

TLS (Transport Layer Security) origination needs three objects that only work together: a `ServiceEntry`, a `VirtualService` and a `DestinationRule`. The endpoint reports the scheme it received, so you can see clearly whether the sidecar proxy did the TLS.

---

## Step 1: Look at the starting state

Read the endpoint's address, then try two calls from `tester`: plain HTTP to the TLS port, and HTTPS done by the application itself. Then read the last line of the `tester` pod's access log, which is the sidecar proxy's record of each request or connection:

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

The output below is shortened: some columns of `kubectl get pod -o wide` and the end of the access log line are left out.

```text
endpoint: 10.244.0.16
NAME         READY   STATUS    IP
secure-api   1/1     Running   10.244.0.16
plain to 8443: 000
scheme=https
[2026-09-27T12:31:05.442Z] "- - -" 0 - - - "-" 705 5923 212 - "-" "-" "-" "-" "10.244.0.16:8443" ...
```

This shows three facts. The endpoint refuses plain HTTP. It answers `scheme=https` when it receives TLS. And when the *application* does the TLS, the proxy's log line is `"- - -"`: no method, no path, no status. That last line is the problem this lab solves.

---

## Step 2: Add the host with both ports

A `ServiceEntry` adds a host outside the mesh to the mesh's service registry, so the sidecar proxy knows its name, address and ports. Make sure the endpoint's address is in a variable:

```sh
SECURE=$(cat /tmp/secure-ip)
```

Replace `<SECURE>` in the YAML below with the real address. To see it, run `echo $SECURE`.

Save this as `serviceentry-secure-api.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: ServiceEntry
metadata:
  name: secure-api
  namespace: tlsorig-demo
spec:
  hosts:
    - secure.example.com
  addresses:
    - <SECURE>
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
    - address: <SECURE>
```

Apply it:

```sh
kubectl apply -f serviceentry-secure-api.yaml
```

Declare **both ports**. Port 8080 with protocol `HTTP` is where the application's plain request arrives, and it is the reason the proxy can read that request. Port 8443 with protocol `HTTPS` is where the encrypted request goes. Many people declare only 8443 on the first try. Then the redirect in the next step has no HTTP port to match.

---

## Step 3: Route port 8080 to port 8443

A `VirtualService` holds routing rules for a host. This one matches requests on port 8080 and sends them to the same host on port 8443. Writing the manifest to a file is a good exam habit: you can read it again, edit it and apply it again.

Save this as `virtualservice-secure-api.yaml`:

```yaml
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
```

Apply it:

```sh
kubectl apply -f virtualservice-secure-api.yaml
```

The **host stays the same**. Only the port changes.

Test now, before you add the third object, to see the failure in between:

```sh
SECURE=$(cat /tmp/secure-ip)
kubectl -n tlsorig-demo exec deploy/tester -- \
  curl -s -o /dev/null -w 'without DestinationRule: %{http_code}\n' --max-time 15 "http://$SECURE:8080/"
```

```text
without DestinationRule: 503
```

The request now reaches port 8443, but as plain HTTP, and the endpoint drops it. Each missing object has its own failure, and this `503` is the one for a missing `DestinationRule`.

---

## Step 4: Originate the TLS

A `DestinationRule` holds the traffic policy for a destination, including how the proxy connects to it. Its `tls` block makes the proxy open a TLS connection.

Save this as `destinationrule-secure-api.yaml`:

```yaml
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
```

Apply it:

```sh
kubectl apply -f destinationrule-secure-api.yaml
```

Three details matter:

- **`portLevelSettings` for 8443, not the top of `trafficPolicy`.** A top-level `tls` also applies to port 8080. The proxy would then try to use TLS on the plain side too, and you get a `503` from an object that looks correct.
- **`sni: secure.example.com`.** SNI (Server Name Indication) is the server name the client sends at the start of the TLS handshake. The proxy is the TLS client now, so it must send the server name. This endpoint's certificate carries that name.
- **`insecureSkipVerify: true`**, because the certificate is self-signed and no certificate authority in the proxy's trust store issued it. In production you set `caCertificates` instead. Here it is a lab shortcut. Without it, the handshake fails and the grader's request fails too.

---

## Step 5: Run the decisive test

Call the endpoint over plain HTTP on port 8080:

```sh
SECURE=$(cat /tmp/secure-ip)
kubectl -n tlsorig-demo exec deploy/tester -- \
  curl -s -w '\nstatus: %{http_code}\n' --max-time 15 "http://$SECURE:8080/"
```

```text
scheme=https
status: 200
```

An `http://` call returns `200`, and the endpoint reports **`scheme=https`**. The endpoint speaks only TLS, so it could only answer if the `tester` pod's sidecar proxy opened the TLS connection. The application did not change.

---

## Step 6: Confirm the proxy can read the request

Read the access log again, and look for the TLS transport socket on the proxy's Envoy cluster for the host. An Envoy cluster is the proxy's group of endpoints for one host and port, and a cluster that uses TLS has a transport socket named `envoy.transport_sockets.tls`:

```sh
kubectl -n tlsorig-demo logs deploy/tester -c istio-proxy --tail=1
istioctl proxy-config cluster deploy/tester -n tlsorig-demo --fqdn secure.example.com -o json \
  | grep -A3 transportSocket | head -5
```

The output below is shortened: part of the access log line is left out.

```text
[2026-09-27T12:44:18.907Z] "GET / HTTP/1.1" 200 - via_upstream - "-" 0 14 3 2 "-" "curl/8.5.0" ... "secure.example.com:8443"
"transportSocket": {
  "name": "envoy.transport_sockets.tls",
```

Compare this log line with the one from step 1. It now has a method, a path and a status where there were dashes. So every HTTP-level (layer 7) feature of Istio now applies to this call. The `transportSocket` on the cluster confirms the TLS from the proxy's side.

If you want to see a layer 7 feature work, add a `timeout` to the `VirtualService`.

---

## Common Mistakes

- **Declaring only port 8443.** The plain request has no HTTP port to arrive on, and the redirect matches nothing.
- **`tls` at the top of `trafficPolicy`.** It also applies to 8080 and breaks the plain side: a `503` from an object that looks correct.
- **Leaving out `sni`.** This endpoint's certificate names `secure.example.com`. Without SNI, the handshake has no server name to select on.
- **Leaving out `insecureSkipVerify`.** The certificate is self-signed, so verification fails and the handshake is rejected.
- **Leaving out the `VirtualService`.** The request stays on 8080, and the endpoint never sees a TLS handshake.
- **Pointing the `VirtualService` at the IP address instead of the host.** It must name the `ServiceEntry` host.
- **Calling `https://` from the client.** Then the sidecar proxy sees an encrypted stream, and none of this applies.
- **Creating a Service in `outside-mesh`.** That adds the endpoint to the service registry in another way, and the grader fails it.
