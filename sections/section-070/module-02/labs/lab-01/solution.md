# Solution Walkthrough

TLS (Transport Layer Security) origination means that the sidecar proxy of the client opens the TLS connection itself, so the application can keep sending plain HTTP. It needs three objects that only work together: a `ServiceEntry`, a `VirtualService` and a `DestinationRule`. The endpoint reports the scheme that it received, so you can see clearly whether the proxy did the TLS. Items 1 and 2 are the `ServiceEntry`. Item 3 is the `VirtualService`, and the walkthrough shows the failure when the third object is missing. Items 4 and 5 are the `DestinationRule`. Items 6 to 14 prove the result.

---

## Start: Look At The Starting State

The task says that `secure-api` listens only on port 8443, with TLS. Read the address of the endpoint, and check the namespaces. Then try two calls from `tester`: plain HTTP to the TLS port, and HTTPS done by the application itself. Read the last line of the access log of the `tester` pod after that. The sidecar proxy is the Envoy container that Istio adds to a pod, and its access log has one line for each request or connection. The log line is shortened to 200 characters:

```sh
SECURE=$(cat /tmp/secure-ip)
echo "endpoint: $SECURE"
kubectl -n outside-mesh get pod secure-api -o wide | awk '{print $1,$2,$3,$6}'
kubectl -n outside-mesh get svc
kubectl -n tlsorig-demo get serviceentry,virtualservice,destinationrule
kubectl -n tlsorig-demo exec deploy/tester -- \
  curl -s -o /dev/null -w 'plain to 8443: %{http_code}\n' --max-time 10 "http://$SECURE:8443/"
kubectl -n tlsorig-demo exec deploy/tester -- curl -sk --max-time 10 "https://$SECURE:8443/"
sleep 2
kubectl -n tlsorig-demo logs deploy/tester -c istio-proxy --tail=1 | cut -c1-200
kubectl -n outside-mesh get pod secure-api -o custom-columns=NAME:.metadata.name,UID:.metadata.uid
```

```text
endpoint: 10.244.0.8
NAME READY STATUS IP
secure-api 1/1 Running 10.244.0.8
No resources found in outside-mesh namespace.
No resources found in tlsorig-demo namespace.
plain to 8443: 400
scheme=https
[2026-10-20T22:07:59.481Z] "- - -" 0 - - - "-" 1747 2193 3 - "-" "-" "-" "-" "10.244.0.8:8443" PassthroughCluster 10.244.0.9:33010 10.244.0.8:8443 10.244.0.9:33008 - -
NAME         UID
secure-api   358a6362-098a-4352-abb1-25d13e22aaf9
```

This shows three facts. The endpoint rejects plain HTTP on its TLS port (status `400`). It answers `scheme=https` when it receives TLS. And when the application does the TLS, the log line of the proxy is `"- - -"` with the cluster `PassthroughCluster`: no method, no path and no status, because the proxy only passes encrypted bytes. That last line is the problem this lab solves. The address of your run will differ. The last output is the state that item 14 must keep.

---

## Items 1 And 2: The `ServiceEntry` With Both Ports

> **Task item 1:** Create a `ServiceEntry` named **`secure-api`** in `tlsorig-demo` for host **`secure.example.com`**, with the endpoint's address in `spec.addresses`, `location: MESH_EXTERNAL`, `resolution: STATIC`, and an `endpoints` entry for that address.
>
> **Task item 2:** Declare **two** ports on it:
>
> * **8080**, name `http`, protocol **`HTTP`**: where the application's plain request arrives
> * **8443**, name `https`, protocol **`HTTPS`**: where the encrypted request goes

A `ServiceEntry` adds a host outside the mesh to the service registry, which is the list of hosts that `istiod`, the Istio control plane, knows about. Declare both ports. Port 8080 with the protocol `HTTP` is where the plain request of the application arrives, and it is the reason the proxy can read that request. Port 8443 with the protocol `HTTPS` is where the encrypted request goes. Many people declare only 8443 on the first try. Then the redirect of the next item has no HTTP port to match.

Replace `<SECURE>` in the YAML with the address of the endpoint. To see it, run `echo $SECURE`. Save this as `serviceentry-secure-api.yaml`:

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

```text
serviceentry.networking.istio.io/secure-api created
```

Check items 1 and 2. Print the spec:

```sh
kubectl -n tlsorig-demo get serviceentry secure-api -o jsonpath='{.spec}{"\n"}'
```

```text
{"addresses":["10.244.0.8"],"endpoints":[{"address":"10.244.0.8"}],"hosts":["secure.example.com"],"location":"MESH_EXTERNAL","ports":[{"name":"http","number":8080,"protocol":"HTTP"},{"name":"https","number":8443,"protocol":"HTTPS"}],"resolution":"STATIC"}
```

The object has the host, the address, `MESH_EXTERNAL`, `STATIC`, one endpoint, and the two ports with the right protocols.

---

## Item 3: Route Port 8080 To Port 8443

> **Task item 3:** Create a `VirtualService` named **`secure-api`** for `secure.example.com` that matches **port 8080** and routes to **port 8443** on the same host.

A `VirtualService` holds the routing rules for a host. This one matches requests that arrive on port 8080, and sends them to the same host on port 8443. The host stays the same. Only the port changes. It must name the host of the `ServiceEntry` and not the IP address. Save this as `virtualservice-secure-api.yaml`:

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

```text
virtualservice.networking.istio.io/secure-api created
```

Check item 3. Print the spec. Then test now, before you add the third object, to see the failure in between:

```sh
kubectl -n tlsorig-demo get virtualservice secure-api -o jsonpath='{.spec}{"\n"}'
kubectl -n tlsorig-demo exec deploy/tester -- \
  curl -s -o /dev/null -w 'without DestinationRule: %{http_code}\n' --max-time 15 "http://$SECURE:8080/"
```

```text
{"hosts":["secure.example.com"],"http":[{"match":[{"port":8080}],"route":[{"destination":{"host":"secure.example.com","port":{"number":8443}}}]}]}
without DestinationRule: 400
```

The request reaches port 8443 now, but as plain HTTP, and the endpoint rejects it with `400`. Each missing object has its own failure, and this one is the failure of a missing `DestinationRule`. If the status is another one, wait a few seconds for `istiod` to send the rule to the proxy, and try again.

---

## Items 4 And 5: Originate The TLS In The `DestinationRule`

> **Task item 4:** Create a `DestinationRule` named **`secure-api`** for `secure.example.com` with `trafficPolicy.portLevelSettings` for **port 8443** only, setting `tls.mode` to **`SIMPLE`** and `tls.sni` to **`secure.example.com`**.
>
> **Task item 5:** The endpoint uses a **self-signed** certificate, so add `insecureSkipVerify: true` to that `tls` block. In production you would set `caCertificates` instead. Here it is a lab shortcut: without it, the proxy rejects the certificate and the grader's request fails.

A `DestinationRule` holds the traffic policy for a destination, including how the proxy connects to it. Its `tls` block makes the proxy open a TLS connection. Three details matter:

- Put `tls` under `portLevelSettings` for port 8443, and not at the top of `trafficPolicy`. A top-level `tls` also applies to port 8080. The proxy would then try to use TLS on the plain side too, and you get an error from an object that looks correct.
- `sni: secure.example.com`. SNI (Server Name Indication) is the server name that the client sends at the start of the TLS handshake. The proxy is the TLS client now, so it must send the server name. The certificate of this endpoint carries that name.
- `insecureSkipVerify: true`, because the certificate is self-signed, and no certificate authority in the trust store of the proxy issued it. In production you set `caCertificates` instead.

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

```text
destinationrule.networking.istio.io/secure-api created
```

Check items 4 and 5. Print the spec:

```sh
kubectl -n tlsorig-demo get destinationrule secure-api -o jsonpath='{.spec}{"\n"}'
```

```text
{"host":"secure.example.com","trafficPolicy":{"portLevelSettings":[{"port":{"number":8443},"tls":{"insecureSkipVerify":true,"mode":"SIMPLE","sni":"secure.example.com"}}]}}
```

The `tls` block is under `portLevelSettings` for port 8443. It has the mode `SIMPLE`, the `sni` of the host, and `insecureSkipVerify: true`.

---

## Items 7 And 8: The Decisive Test

> **Task item 7:** `GET http://<secure-ip>:8080/` from `tester` returns **200**.
>
> **Task item 8:** The response body contains **`scheme=https`**. The endpoint received a TLS connection, which is only possible if the sidecar proxy originated it.

Call the endpoint over plain HTTP on port 8080. Item 6 of the task says that the application must never use `https://`:

```sh
kubectl -n tlsorig-demo exec deploy/tester -- \
  curl -s -w '\nstatus: %{http_code}\n' --max-time 15 "http://$SECURE:8080/"
```

```text
scheme=https

status: 200
```

The `http://` call returns `200`, and the endpoint reports `scheme=https`. The endpoint speaks only TLS, so it could only answer if the sidecar proxy of `tester` opened the TLS connection. The application did not change. Compare the access log line now with the one from the Start section:

```sh
sleep 2
kubectl -n tlsorig-demo logs deploy/tester -c istio-proxy --tail=1 | cut -c1-200
```

```text
[2026-10-20T22:08:26.239Z] "GET / HTTP/1.1" 200 - via_upstream - "-" 0 13 4 3 "-" "curl/8.23.0" "7f0f24df-8105-9e7a-8f9b-fa110c0a63d3" "10.244.0.8:8080" "10.244.0.8:8443" outbound|8443||secure.example
```

The line has a method, a path and a status where there were dashes. So every HTTP feature of Istio applies to this call now, for example a `timeout` in the `VirtualService`.

---

## Items 9 To 12: The Objects Have The Right Shape

> **Task item 9:** The `ServiceEntry` declares both ports with the required protocols, the address, `MESH_EXTERNAL`, `STATIC` and the endpoint.
>
> **Task item 10:** The `VirtualService` matches port 8080 and routes to `secure.example.com` on port 8443.
>
> **Task item 11:** The `DestinationRule`'s `tls` block is under **`portLevelSettings` for port 8443**, not at the top level of `trafficPolicy`. A top-level `tls` also applies to port 8080 and breaks the plain side.
>
> **Task item 12:** `sni` is set to `secure.example.com`.

The outputs of the items 1 to 5 show all four: the `ServiceEntry` with both ports, the `VirtualService` with the match on port 8080 and the route to port 8443, and the `DestinationRule` with `tls` under `portLevelSettings` and `sni: secure.example.com`.

---

## Item 13: The Cluster Has A TLS Transport Socket

> **Task item 13:** The `tester` proxy's cluster for `secure.example.com` has a TLS transport socket.

A cluster is the group of endpoints that the proxy keeps for one host and port. A cluster that uses TLS has a transport socket named `envoy.transport_sockets.tls`:

```sh
istioctl proxy-config cluster deploy/tester -n tlsorig-demo --fqdn secure.example.com | head -5
istioctl proxy-config cluster deploy/tester -n tlsorig-demo --fqdn secure.example.com -o json \
  | grep -B1 -A3 transportSocket | head -12
```

```text
SERVICE FQDN           PORT     SUBSET     DIRECTION     TYPE     DESTINATION RULE
secure.example.com     8080     -          outbound      EDS      secure-api.tlsorig-demo
secure.example.com     8443     -          outbound      EDS      secure-api.tlsorig-demo
        "commonLbConfig": {},
        "transportSocket": {
            "name": "envoy.transport_sockets.tls",
            "typedConfig": {
                "@type": "type.googleapis.com/envoy.extensions.transport_sockets.tls.v3.UpstreamTlsContext",
```

The host has a cluster for each port. The cluster for port 8443 has a transport socket with the type `UpstreamTlsContext`, which confirms the TLS from the side of the proxy.

---

## Item 14: No Service In `outside-mesh`

> **Task item 14:** No Service exists in `outside-mesh`.

```sh
kubectl -n outside-mesh get svc
kubectl -n outside-mesh get pod secure-api -o custom-columns=NAME:.metadata.name,UID:.metadata.uid
```

```text
No resources found in outside-mesh namespace.
NAME         UID
secure-api   358a6362-098a-4352-abb1-25d13e22aaf9
```

There is no Service, and the pod has the same `UID` as before.

---

## Submit

Send the lab for grading:

```sh
astrona submit -c sections/section-070/module-02/labs/lab-01
```

The grader calls the endpoint from `tester` and reads the objects and the cluster.

---

## Mistakes That Fail The Grader

- **Declaring only port 8443 (item 2).** The plain request has no HTTP port to arrive on, and the redirect matches nothing.
- **`tls` at the top of `trafficPolicy` (item 4).** It also applies to 8080 and breaks the plain side.
- **Leaving out `sni` (item 4).** The certificate of this endpoint names `secure.example.com`. Without SNI, the handshake has no server name to select on.
- **Leaving out `insecureSkipVerify` (item 5).** The certificate is self-signed, so verification fails and the handshake is rejected.
- **Leaving out the `VirtualService` (item 3).** The request stays on 8080, and the endpoint never sees a TLS handshake.
- **Pointing the `VirtualService` at the IP address instead of the host (item 3).** It must name the host of the `ServiceEntry`.
- **Calling `https://` from the client (item 6 of the task).** Then the sidecar proxy sees an encrypted stream, and none of this applies.
- **Creating a Service in `outside-mesh` (item 14).** That adds the endpoint to the service registry in another way.
