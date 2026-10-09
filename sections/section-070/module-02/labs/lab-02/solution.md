# Solution

Two objects are wrong. The `VirtualService` matches port `80`, but the shuttle calls port `8080`, so the request is never routed to `8443`. The `DestinationRule` turns on TLS (Transport Layer Security) for port `8080` instead of `8443`. Each mistake has its own symptom, so fix them one at a time and read the shuttle's access log after each fix. The access log is the sidecar proxy's record of each request: one line with the method, path, status code and the Envoy cluster it used.

The outputs below come from a real run. Your pod addresses and timestamps differ.

## Step 1: See the failure

Store the vault's address, send a request from the shuttle, and read the shuttle's access log:

```sh
VAULT_IP=$(kubectl get pod vault -n outpost -o jsonpath='{.status.podIP}')
kubectl exec -n starfleet deploy/shuttle -- curl -s -w "\n%{http_code}\n" http://$VAULT_IP:8080/
kubectl logs -n starfleet deploy/shuttle -c istio-proxy --tail=1
```

```text
upstream connect error or disconnect/reset before headers. retried and the latest reset reason: remote connection failure
503
[2026-10-08T22:51:04.842Z] "GET / HTTP/1.1" 503 URX,UF upstream_reset_before_response_started{remote_connection_failure|delayed_connect_error:_Connection_refused} - "delayed_connect_error:_Connection_refused" 0 121 86 - "-" "curl/8.11.1" "81a126e8-bec2-41a6-902d-014efc188932" "10.244.0.9:8080" "10.244.0.9:8080" outbound|8080||vault.outpost.example - 10.244.0.9:8080 10.244.0.6:53166 - default
```

The response came from the shuttle's proxy (response flag `UF`, upstream connection failure), not from the vault. The Envoy cluster is `outbound|8080||vault.outpost.example` and the upstream address is `10.244.0.9:8080`. The request stayed on port `8080`, where nothing listens. So the `VirtualService` did not route it to `8443`.

## Step 2: Read the objects

Look at the `VirtualService` and the `DestinationRule`:

```sh
kubectl get virtualservice vault -n starfleet -o yaml | sed -n '/^spec:/,$p'
kubectl get destinationrule vault -n starfleet -o yaml | sed -n '/^spec:/,$p'
```

```text
spec:
  hosts:
  - vault.outpost.example
  http:
  - match:
    - port: 80
    route:
    - destination:
        host: vault.outpost.example
        port:
          number: 8443
spec:
  host: vault.outpost.example
  trafficPolicy:
    portLevelSettings:
    - port:
        number: 8080
      tls:
        insecureSkipVerify: true
        mode: SIMPLE
        sni: vault.outpost.example
```

Both mistakes are visible: the `VirtualService` matches port `80`, and the `DestinationRule` turns on TLS for port `8080`. `istioctl analyze` also points at the second one. The output below is shortened to the `vault` line:

```sh
istioctl analyze -n starfleet
```

```text
Warning [IST0129] (DestinationRule starfleet/vault) DestinationRule starfleet/vault in namespace starfleet has TLS mode set to SIMPLE but no caCertificates are set to validate server identity for host: vault.outpost.example at port number:8080
```

The warning itself is about `caCertificates`, but it names the port that has the `tls` block: `8080`, the plain side.

## Step 3: Fix the VirtualService

Match the port the shuttle really calls. Save this as `virtualservice-vault.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: vault
  namespace: starfleet
spec:
  hosts:
  - vault.outpost.example
  http:
  - match:
    - port: 8080
    route:
    - destination:
        host: vault.outpost.example
        port:
          number: 8443
```

Apply it:

```sh
kubectl apply -f virtualservice-vault.yaml
```

Then send a request and read the access log:

```sh
kubectl exec -n starfleet deploy/shuttle -- curl -s -w "\n%{http_code}\n" http://$VAULT_IP:8080/
kubectl logs -n starfleet deploy/shuttle -c istio-proxy --tail=1
```

```text
<html>
<head><title>400 The plain HTTP request was sent to HTTPS port</title></head>
<body>
<center><h1>400 Bad Request</h1></center>
<center>The plain HTTP request was sent to HTTPS port</center>
<hr><center>nginx/1.27.5</center>
</body>
</html>

400
[2026-10-08T22:51:22.247Z] "GET / HTTP/1.1" 400 - via_upstream - "-" 0 255 9 1 "-" "curl/8.11.1" "6a78678f-25d7-436b-836d-5b121a4d601b" "10.244.0.9:8080" "10.244.0.9:8443" outbound|8443||vault.outpost.example 10.244.0.6:43874 10.244.0.9:8080 10.244.0.6:54562 - -
```

This is progress. The request now goes through `outbound|8443||vault.outpost.example`, and the vault itself answers (`via_upstream`). But the request arrives as plain HTTP, because no TLS is configured for port `8443`.

## Step 4: Fix the DestinationRule

Move the `tls` block to port `8443`. Save this as `destinationrule-vault.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: vault
  namespace: starfleet
spec:
  host: vault.outpost.example
  trafficPolicy:
    portLevelSettings:
    - port:
        number: 8443
      tls:
        mode: SIMPLE
        sni: vault.outpost.example
        insecureSkipVerify: true
```

Apply it:

```sh
kubectl apply -f destinationrule-vault.yaml
```

Then send a request and read the access log:

```sh
kubectl exec -n starfleet deploy/shuttle -- curl -s -w "%{http_code}\n" http://$VAULT_IP:8080/
kubectl logs -n starfleet deploy/shuttle -c istio-proxy --tail=1
```

```text
vault: scheme=https
200
[2026-10-08T22:51:38.352Z] "GET / HTTP/1.1" 200 - via_upstream - "-" 0 20 7 3 "-" "curl/8.11.1" "65d8b35a-55d4-4013-a1e3-25e40995afdd" "10.244.0.9:8080" "10.244.0.9:8443" outbound|8443||vault.outpost.example 10.244.0.6:38234 10.244.0.9:8080 10.244.0.6:41366 - -
```

The shuttle sent `http://` to port `8080`, and the vault reports `scheme=https`. The shuttle's sidecar proxy routed the request to `8443` and opened the TLS connection.

## Step 5: Prove TLS is on the right port

An Envoy cluster that uses TLS has a transport socket named `envoy.transport_sockets.tls`. Count these on both clusters in the shuttle's proxy:

```sh
for p in 8080 8443; do
  echo "port $p: $(istioctl proxy-config cluster deploy/shuttle -n starfleet --fqdn vault.outpost.example --port $p -o json | grep -c envoy.transport_sockets.tls)"
done
```

```text
port 8080: 0
port 8443: 1
```

Port `8080` stays plain, and only port `8443` uses TLS. Now submit:

```sh
astrona submit -c sections/section-070/module-02/labs/lab-02
```

---

## Common Mistakes

- **Fixing only one object.** With only the `VirtualService` fixed, you get `400` from the vault. With only the `DestinationRule` fixed, you still get `503 UF`, because the request stays on port `8080`.
- **Putting `tls` at the top level of `trafficPolicy`.** The call works, because the redirect moves every request away from `8080`, but port `8080` uses TLS too. The grader checks that port `8080` has no TLS transport socket.
- **Leaving the old `8080` entry in `portLevelSettings`.** Add `8443`, but also remove the `tls` block for `8080`.
- **Removing `sni` or `insecureSkipVerify`.** The grader checks `sni: vault.outpost.example`. Without `insecureSkipVerify`, the proxy rejects the vault's self-signed certificate.
- **Changing the `ServiceEntry`, or creating a Service in `outpost`.** The `ServiceEntry` was correct, and the vault must stay out of the service registry except through it.
- **Testing too fast.** `kubectl apply` returns before `istiod` has pushed the new configuration to the shuttle's proxy. If the old symptom stays, wait a few seconds and send the request again.
