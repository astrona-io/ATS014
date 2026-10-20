# Solution Walkthrough

Two objects are wrong. The `VirtualService` matches port `80`, but the shuttle calls port `8080`, so the request is never routed to `8443`. The `DestinationRule` turns on TLS (Transport Layer Security) for port `8080` instead of `8443`. Each mistake has its own symptom, so you fix them one at a time and read the access log after each fix. The access log is the record of the sidecar proxy: one line for each request, with the method, the path, the status code and the Envoy cluster that it used. The sidecar proxy is the Envoy container that Istio adds to a pod. The Start section finds both mistakes. Items 2 and 3 are the two fixes, and items 1, 4, 5 and 6 prove the result. The pod addresses and the timestamps of your run differ from the ones in this walkthrough.

---

## Start: See The Failure And Read The Objects

Store the address of the vault, send a request from the `shuttle`, and read its access log. The output is shortened to 120 and 260 characters:

```sh
VAULT_IP=$(kubectl -n outpost get pod vault -o jsonpath='{.status.podIP}')
echo "vault: $VAULT_IP"
kubectl -n starfleet exec deploy/shuttle -- curl -s -w "\n%{http_code}\n" http://$VAULT_IP:8080/
sleep 2
kubectl -n starfleet logs deploy/shuttle -c istio-proxy --tail=1 | cut -c1-260
```

```text
vault: 10.244.0.7
upstream connect error or disconnect/reset before headers. retried and the latest reset reason: remote connection failure
503
[2026-10-20T22:10:28.515Z] "GET / HTTP/1.1" 503 URX,UF upstream_reset_before_response_started{remote_connection_failure|delayed_connect_error:_Connection_refused} - "delayed_connect_error:_Connection_refused" 0 121 67 - "-" "curl/8.11.1" "bf735127-e43b-45cc-8d
```

The answer came from the proxy of the `shuttle` (response flag `UF`, upstream connection failure), not from the vault. The request stayed on port `8080`, where nothing listens. So the `VirtualService` did not route it to `8443`. Read the `VirtualService` and the `DestinationRule`, and let Istio check the namespace:

```sh
kubectl -n starfleet get virtualservice vault -o jsonpath='{.spec}{"\n"}'
kubectl -n starfleet get destinationrule vault -o jsonpath='{.spec}{"\n"}'
istioctl analyze -n starfleet 2>&1 | grep IST
```

```text
{"hosts":["vault.outpost.example"],"http":[{"match":[{"port":80}],"route":[{"destination":{"host":"vault.outpost.example","port":{"number":8443}}}]}]}
{"host":"vault.outpost.example","trafficPolicy":{"portLevelSettings":[{"port":{"number":8080},"tls":{"insecureSkipVerify":true,"mode":"SIMPLE","sni":"vault.outpost.example"}}]}}
Warning [IST0129] (DestinationRule starfleet/vault) DestinationRule starfleet/vault in namespace starfleet has TLS mode set to SIMPLE but no caCertificates are set to validate server identity for host: vault.outpost.example at port number:8080
```

Both mistakes are visible. The `VirtualService` matches port `80`, and the `DestinationRule` turns on TLS for port `8080`. The warning `IST0129` is about `caCertificates`, but it names the port that has the `tls` block: `8080`, the plain side.

Save the state that items 1 and 6 must keep:

```sh
kubectl -n starfleet get serviceentry vault -o jsonpath='generation={.metadata.generation} uid={.metadata.uid}{"\n"}'
kubectl -n outpost get pod vault -o custom-columns=NAME:.metadata.name,UID:.metadata.uid
kubectl -n outpost get svc
kubectl -n starfleet get deploy -o custom-columns=NAME:.metadata.name,UID:.metadata.uid
```

```text
generation=1 uid=3eed69e8-a231-4630-827b-d5adab89c796
NAME    UID
vault   92918de9-e04d-452d-9564-873295d4adf8
No resources found in outpost namespace.
NAME      UID
shuttle   7827e9fe-8969-48df-bdff-ebc76aca9763
```

---

## Item 2: Fix The `VirtualService`

> **Task item 2:** The `VirtualService` named `vault` matches requests on **port `8080`** and routes them to host `vault.outpost.example` on **port `8443`**.

A `VirtualService` holds the routing rules for a host. Match the port that the shuttle really calls, which is `8080`. Save this as `virtualservice-vault.yaml`:

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

```text
virtualservice.networking.istio.io/vault configured
```

Send a request, and read the access log. Wait a few seconds after the apply first, because `istiod`, the Istio control plane, must send the change to the proxy:

```sh
kubectl -n starfleet exec deploy/shuttle -- curl -s -w "\n%{http_code}\n" http://$VAULT_IP:8080/ | sed 's/<[^>]*>//g' | grep -v '^$' | head -4
sleep 2
kubectl -n starfleet logs deploy/shuttle -c istio-proxy --tail=1 | cut -c1-260
```

```text
400 The plain HTTP request was sent to HTTPS port

400 Bad Request
[2026-10-20T22:10:39.768Z] "GET / HTTP/1.1" 400 - via_upstream - "-" 0 255 1 0 "-" "curl/8.11.1" "a5504ee4-b2de-45a2-a9d6-9b5e26dee177" "10.244.0.7:8080" "10.244.0.7:8443" outbound|8443||vault.outpost.example 10.244.0.6:41538 10.244.0.7:8080 10.244.0.6:38592 -
```

This is progress. The request goes through the cluster `outbound|8443||vault.outpost.example` now, and the vault itself answers (`via_upstream`). A cluster is the group of endpoints that the proxy keeps for one host and port. But the request arrives as plain HTTP, because no TLS is configured for port `8443`. The `sed` command removes the HTML tags of the answer.

---

## Item 3: Fix The `DestinationRule`

> **Task item 3:** The `DestinationRule` named `vault` sets `tls` with `mode: SIMPLE` and `sni: vault.outpost.example` under `trafficPolicy.portLevelSettings` for **port `8443` only**. Port `8080` must not use TLS, and there must be no top-level `tls`. Keep `insecureSkipVerify: true`: the vault uses a self-signed certificate.

A `DestinationRule` holds the traffic policy for a destination, including how the proxy connects to it. Move the `tls` block from port `8080` to port `8443`. Remove the entry for `8080`. SNI (Server Name Indication) is the server name that the proxy sends at the start of the TLS handshake. Save this as `destinationrule-vault.yaml`:

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

```text
destinationrule.networking.istio.io/vault configured
```

Send the request again, and read the access log:

```sh
kubectl -n starfleet exec deploy/shuttle -- curl -s -w "\n%{http_code}\n" http://$VAULT_IP:8080/
sleep 2
kubectl -n starfleet logs deploy/shuttle -c istio-proxy --tail=1 | cut -c1-260
```

```text
vault: scheme=https

200
[2026-10-20T22:10:50.067Z] "GET / HTTP/1.1" 200 - via_upstream - "-" 0 20 5 5 "-" "curl/8.11.1" "457527c2-f649-44b9-8d7a-e332b66113bb" "10.244.0.7:8080" "10.244.0.7:8443" outbound|8443||vault.outpost.example 10.244.0.6:60844 10.244.0.7:8080 10.244.0.6:50550 - 
```

The shuttle sent `http://` to port `8080`, and the vault reports `scheme=https`. The sidecar proxy routed the request to `8443` and opened the TLS connection.

Check items 2 and 3 once more with the final objects:

```sh
kubectl -n starfleet get virtualservice vault -o jsonpath='{.spec}{"\n"}'
kubectl -n starfleet get destinationrule vault -o jsonpath='{.spec}{"\n"}'
```

```text
{"hosts":["vault.outpost.example"],"http":[{"match":[{"port":8080}],"route":[{"destination":{"host":"vault.outpost.example","port":{"number":8443}}}]}]}
{"host":"vault.outpost.example","trafficPolicy":{"portLevelSettings":[{"port":{"number":8443},"tls":{"insecureSkipVerify":true,"mode":"SIMPLE","sni":"vault.outpost.example"}}]}}
```

The `VirtualService` matches port `8080` and routes to port `8443`. The `DestinationRule` has one `portLevelSettings` entry, for port `8443`, with the mode `SIMPLE`, the `sni`, and `insecureSkipVerify: true`. There is no top-level `tls`.

---

## Item 4: TLS Is On The Right Port

> **Task item 4:** In the `shuttle`'s proxy, the cluster for port `8443` of `vault.outpost.example` has a TLS transport socket, and the cluster for port `8080` has none.

A cluster that uses TLS has a transport socket named `envoy.transport_sockets.tls`. Count it on both clusters in the proxy of the `shuttle`:

```sh
for p in 8080 8443; do
  echo "port $p: $(istioctl proxy-config cluster deploy/shuttle -n starfleet --fqdn vault.outpost.example --port $p -o json | grep -c envoy.transport_sockets.tls)"
done
```

```text
port 8080: 0
port 8443: 1
```

Port `8080` stays plain, and only port `8443` uses TLS.

---

## Item 5: The Decisive Test

> **Task item 5:** `GET http://<VAULT_IP>:8080/` from the `shuttle` returns **`200`**, and the response contains **`scheme=https`**.

The output of item 3 is the test: the answer is `vault: scheme=https` with the status `200`, from a call to `http://` on port `8080`.

---

## Items 1 And 6: Nothing Else Changed

> **Task item 1:** The `ServiceEntry` named `vault` is **left unchanged**.
>
> **Task item 6:** Do not change the `shuttle`, the `vault` pod, or the address the shuttle calls. Do not create a Service in `outpost`.

Run the four commands from the Start section that print the identity again:

```sh
kubectl -n starfleet get serviceentry vault -o jsonpath='generation={.metadata.generation} uid={.metadata.uid}{"\n"}'
kubectl -n outpost get pod vault -o custom-columns=NAME:.metadata.name,UID:.metadata.uid
kubectl -n outpost get svc
kubectl -n starfleet get deploy -o custom-columns=NAME:.metadata.name,UID:.metadata.uid
```

```text
generation=1 uid=3eed69e8-a231-4630-827b-d5adab89c796
NAME    UID
vault   92918de9-e04d-452d-9564-873295d4adf8
No resources found in outpost namespace.
NAME      UID
shuttle   7827e9fe-8969-48df-bdff-ebc76aca9763
```

The output is the same as before. The `ServiceEntry` still has `generation=1`, the vault pod and the `shuttle` have the same `UID` values, and there is no Service in `outpost`.

---

## Submit

Send the lab for grading:

```sh
astrona submit -c sections/section-070/module-02/labs/lab-02
```

The grader sends real requests from the `shuttle` pod and reads its proxy configuration.

---

## Mistakes That Fail The Grader

- **Fixing only one object (items 2 and 3).** With only the `VirtualService` fixed, you get `400` from the vault. With only the `DestinationRule` fixed, you still get `503` with `UF`, because the request stays on port `8080`.
- **Putting `tls` at the top level of `trafficPolicy` (item 3).** The call works, because the redirect moves every request away from `8080`, but port `8080` uses TLS too. The task checks that port `8080` has no TLS transport socket.
- **Leaving the old `8080` entry in `portLevelSettings` (items 3 and 4).** Add `8443`, and remove the `tls` block for `8080`.
- **Removing `sni` or `insecureSkipVerify` (item 3).** The task checks `sni: vault.outpost.example`. Without `insecureSkipVerify`, the proxy rejects the self-signed certificate of the vault.
- **Changing the `ServiceEntry`, or creating a Service in `outpost` (items 1 and 6).** The `ServiceEntry` was correct, and the vault must stay out of the service registry except through it.
- **Testing too fast (items 2 to 5).** `kubectl apply` returns before `istiod` has pushed the new configuration to the proxy. If the old symptom stays, wait a few seconds and send the request again.
