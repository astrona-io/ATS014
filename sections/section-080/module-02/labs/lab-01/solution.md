# Solution Walkthrough

You build five objects, one for each of the first five items of the task. Items 6 to 11 are the checks the grader runs. The walkthrough proves items 6 to 11 with real requests after the objects exist. An egress gateway is an Envoy proxy at the edge of the mesh that outbound traffic passes through. In this lab it also starts the TLS (Transport Layer Security) connection to the partner server, so the `tester` pod only sends plain `http://`.

The outputs below come from a real run. Your pod addresses, timestamps and UIDs differ.

---

## Start: Look At The Starting State

Read the address of the partner server. Then send two requests from `tester`: one with plain HTTP to port `8443`, and one with TLS to the same port. Count the lines for `partner.example.com` in the egress gateway access log, where the gateway writes one line per request:

```sh
PARTNER=$(cat /tmp/partner-ip)
echo "partner: $PARTNER"
kubectl -n egwtls-demo exec deploy/tester -- curl -s -o /dev/null -w "plain to 8443: %{http_code}\n" --max-time 10 http://$PARTNER:8443/
kubectl -n egwtls-demo exec deploy/tester -- curl -sk --max-time 10 https://$PARTNER:8443/
kubectl -n istio-system logs deploy/istio-egressgateway --tail=-1 | grep -c partner.example.com
```

```text
partner: 10.244.0.8
plain to 8443: 400
scheme=https
0
```

The partner server rejects plain text with `400` and answers a TLS request with `scheme=https`. The egress gateway has no log line for the partner yet.

Check that no Istio object exists, and save the state that item 11 says must stay the same:

```sh
kubectl -n egwtls-demo get serviceentry,gateway,destinationrule,virtualservice
kubectl -n outside-mesh get svc
kubectl -n egwtls-demo get deploy -o custom-columns=NAME:.metadata.name,READY:.status.readyReplicas,UID:.metadata.uid
kubectl -n outside-mesh get pods -o custom-columns=NAME:.metadata.name,PHASE:.status.phase,UID:.metadata.uid
```

```text
No resources found in egwtls-demo namespace.
No resources found in outside-mesh namespace.
NAME     READY   UID
tester   1       1726d9ab-b9b5-45dc-836a-6739cbb176c0
NAME          PHASE     UID
partner-api   Running   58d1d6c3-3327-43c2-95bf-6cc85ec24ae2
```

---

## Item 1: Add The Partner To The Service Registry

> **Task item 1:** A `ServiceEntry` named `partner` for `partner.example.com`, with the partner's IP address in `spec.addresses`, `MESH_EXTERNAL`, `STATIC`, an `endpoints` entry, and two ports: `8080` `http` `HTTP` and `8443` `https` `HTTPS`.

A `ServiceEntry` adds a host to the service registry, the list of hosts and endpoints that `istiod` knows about. In the YAML, replace `<PARTNER>` in both places with the address that `echo $PARTNER` prints. Save this as `serviceentry-partner.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: ServiceEntry
metadata:
  name: partner
  namespace: egwtls-demo
spec:
  hosts:
    - partner.example.com
  addresses:
    - <PARTNER>
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
    - address: <PARTNER>
```

Apply it:

```sh
kubectl apply -f serviceentry-partner.yaml
```

Then check the result:

```sh
kubectl -n egwtls-demo get serviceentry partner -o jsonpath='{.spec}{"\n"}'
```

```text
{"addresses":["10.244.0.8"],"endpoints":[{"address":"10.244.0.8"}],"hosts":["partner.example.com"],"location":"MESH_EXTERNAL","ports":[{"name":"http","number":8080,"protocol":"HTTP"},{"name":"https","number":8443,"protocol":"HTTPS"}],"resolution":"STATIC"}
```

The port `8080` is the port the client calls. The port `8443` is the port the egress gateway calls on the partner. Both ports must be in the `ServiceEntry`, or the mesh has no cluster for the second hop.

---

## Item 2: Open Port 8080 On The Egress Gateway

> **Task item 2:** A `Gateway` named `egress-gateway` that selects `istio: egressgateway` and opens port `8080` with protocol `HTTP` for `partner.example.com`.

A `Gateway` configures the listener of a gateway proxy. This one selects the pods of the egress gateway by label. Save this as `gateway-egress-gateway.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: Gateway
metadata:
  name: egress-gateway
  namespace: egwtls-demo
spec:
  selector:
    istio: egressgateway
  servers:
    - port:
        number: 8080
        name: http
        protocol: HTTP
      hosts:
        - partner.example.com
```

Apply it:

```sh
kubectl apply -f gateway-egress-gateway.yaml
```

Then check the result:

```sh
kubectl -n egwtls-demo get gateway egress-gateway -o jsonpath='{.spec}{"\n"}'
```

```text
{"selector":{"istio":"egressgateway"},"servers":[{"hosts":["partner.example.com"],"port":{"name":"http","number":8080,"protocol":"HTTP"}}]}
```

The listener stays plain HTTP. The TLS connection starts later, on the way from the gateway to the partner.

---

## Item 3: Add The Subset For The Egress Gateway

> **Task item 3:** A `DestinationRule` named `egressgateway-for-partner` for `istio-egressgateway.istio-system.svc.cluster.local`, with one subset named `partner` and no labels.

A `DestinationRule` sets what happens after routing picks a host. A subset is a named group of pods. Rule 1 of the `VirtualService` in the next item sends requests to this subset. Save this as `destinationrule-egressgateway-for-partner.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: egressgateway-for-partner
  namespace: egwtls-demo
spec:
  host: istio-egressgateway.istio-system.svc.cluster.local
  subsets:
    - name: partner
```

Apply it:

```sh
kubectl apply -f destinationrule-egressgateway-for-partner.yaml
```

Then check the result:

```sh
kubectl -n egwtls-demo get destinationrule egressgateway-for-partner -o jsonpath='{.spec}{"\n"}'
```

```text
{"host":"istio-egressgateway.istio-system.svc.cluster.local","subsets":[{"name":"partner"}]}
```

---

## Item 4: Route Through The Egress Gateway

> **Task item 4:** A `VirtualService` named `partner-through-egress` for `partner.example.com` with `mesh` and `egress-gateway` in `gateways`. Rule 1: `gateways: [mesh]`, port `8080`, to the egress gateway Service, subset `partner`, port `8080`. Rule 2: `gateways: [egress-gateway]`, port `8080`, to `partner.example.com` port `8443`.

A `VirtualService` sets how requests to a host are routed. This one applies in two places. On the `mesh` gateway, it is read by the sidecar proxy of `tester`, and rule 1 sends the request to the egress gateway. On `egress-gateway`, it is read by the gateway proxy, and rule 2 sends the request on to the partner. Save this as `virtualservice-partner-through-egress.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: partner-through-egress
  namespace: egwtls-demo
spec:
  hosts:
    - partner.example.com
  gateways:
    - mesh
    - egress-gateway
  http:
    - match:
        - gateways: [mesh]
          port: 8080
      route:
        - destination:
            host: istio-egressgateway.istio-system.svc.cluster.local
            subset: partner
            port:
              number: 8080
    - match:
        - gateways: [egress-gateway]
          port: 8080
      route:
        - destination:
            host: partner.example.com
            port:
              number: 8443
```

Apply it:

```sh
kubectl apply -f virtualservice-partner-through-egress.yaml
```

Then check the result and run the analyzer:

```sh
kubectl -n egwtls-demo get virtualservice partner-through-egress -o jsonpath='gateways={.spec.gateways}{"\n"}{range .spec.http[*]}{.match}{" -> "}{.route[0].destination.host}{" "}{.route[0].destination.subset}{":"}{.route[0].destination.port.number}{"\n"}{end}'
istioctl analyze -n egwtls-demo
```

```text
gateways=["mesh","egress-gateway"]
[{"gateways":["mesh"],"port":8080}] -> istio-egressgateway.istio-system.svc.cluster.local partner:8080
[{"gateways":["egress-gateway"],"port":8080}] -> partner.example.com :8443

✔ No validation issues found when analyzing namespace: egwtls-demo.
```

Now send one request. The route exists, but nothing starts TLS yet:

```sh
kubectl -n egwtls-demo exec deploy/tester -- curl -s -o /dev/null -w 'without origination: %{http_code}\n' --max-time 20 http://partner.example.com:8080/
```

```text
without origination: 400
```

This is the same `400` as in the starting state. The request now passes through the egress gateway, but the gateway sends plain text to port `8443`, and the partner rejects it. Item 5 fixes this.

---

## Item 5: Start TLS At The Egress Gateway

> **Task item 5:** A `DestinationRule` named `originate-tls-for-partner` for `partner.example.com`, with `portLevelSettings` for port `8443`: `tls.mode: SIMPLE`, `tls.sni: partner.example.com`, `insecureSkipVerify: true`, and `exportTo: [istio-system]`.

TLS origination means that a proxy opens the TLS connection for a client that sends plain text. A `DestinationRule` is applied by the proxy that calls the host. Here that is the egress gateway, which runs in `istio-system`. With `exportTo: [istio-system]`, only proxies in that namespace get the rule, so the sidecar proxy of `tester` keeps a plain cluster. Save this as `destinationrule-originate-tls-for-partner.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: originate-tls-for-partner
  namespace: egwtls-demo
spec:
  exportTo:
    - istio-system
  host: partner.example.com
  trafficPolicy:
    portLevelSettings:
      - port:
          number: 8443
        tls:
          mode: SIMPLE
          sni: partner.example.com
          insecureSkipVerify: true
```

Apply it:

```sh
kubectl apply -f destinationrule-originate-tls-for-partner.yaml
```

Then check the result:

```sh
kubectl -n egwtls-demo get destinationrule originate-tls-for-partner -o jsonpath='{.spec}{"\n"}'
```

```text
{"exportTo":["istio-system"],"host":"partner.example.com","trafficPolicy":{"portLevelSettings":[{"port":{"number":8443},"tls":{"insecureSkipVerify":true,"mode":"SIMPLE","sni":"partner.example.com"}}]}}
```

`insecureSkipVerify: true` is needed because the partner uses a self-signed certificate. Without it, the gateway rejects the certificate.

---

## Item 6: Send A Plain Request And Get `scheme=https`

> **Task item 6:** `GET http://partner.example.com:8080/` from `tester` returns `200`, and the body contains `scheme=https`.

Send the request from `tester`:

```sh
kubectl -n egwtls-demo exec deploy/tester -- curl -s -w '\nstatus: %{http_code}\n' --max-time 20 http://partner.example.com:8080/
```

```text
scheme=https

status: 200
```

The client sent `http://` to port `8080`, and the partner reports `scheme=https`. The egress gateway opened the TLS connection. If you still see `400`, wait a few seconds and send the request again. `istiod` needs a moment to push the new configuration to the proxies.

---

## Item 7: Find The Request In The Egress Gateway Log

> **Task item 7:** The egress gateway's own access log gains a line for the request, with the upstream on port `8443`.

Send one request, wait for the log, and print the last line for the partner (cut to 260 characters). In the starting state, the gateway had no line for the partner. In the real run, this request added exactly one:

```sh
kubectl -n egwtls-demo exec deploy/tester -- curl -s -o /dev/null --max-time 20 http://partner.example.com:8080/
sleep 4
kubectl -n istio-system logs deploy/istio-egressgateway --tail=5 | grep partner.example.com | tail -1 | cut -c1-260
```

```text
[2026-10-20T22:27:48.562Z] "GET / HTTP/1.1" 200 - via_upstream - "-" 0 13 1 1 "10.244.0.9" "curl/8.23.0" "04a030b0-c78b-904d-98d5-a9c3f4dcfcbf" "partner.example.com:8080" "10.244.0.8:8443" outbound|8443||partner.example.com 10.244.0.6:37058 10.244.0.6:8080 10.
```

The log has one new line for each request. The request line arrived on the gateway at `:8080`. The upstream is `10.244.0.8:8443`, and the cluster is `outbound|8443||partner.example.com`. The gateway logged the request, so the gateway handled it, not the sidecar proxy alone.

---

## Item 8: Compare The TLS Settings Of Two Proxies

> **Task item 8:** The egress gateway's cluster for `partner.example.com` has a TLS `transportSocket`, and the `tester` sidecar proxy's cluster does not.

A `transportSocket` is the part of an Envoy cluster that holds the TLS settings for connections to its endpoints. Count it in the cluster of each proxy:

```sh
echo -n "gateway: "; istioctl proxy-config cluster deploy/istio-egressgateway -n istio-system --fqdn partner.example.com -o json | grep -c transportSocket
echo -n "sidecar: "; istioctl proxy-config cluster deploy/tester -n egwtls-demo --fqdn partner.example.com -o json | grep -c transportSocket
```

```text
gateway: 1
sidecar: 0
```

Only the egress gateway has the TLS settings. This is the effect of `exportTo: [istio-system]`. Without it, the count for the sidecar proxy would be `1` too, and the client would try TLS toward a gateway that expects plain HTTP.

---

## Items 9 And 10: Read The Port And The Placement

> **Task item 9:** Rule 2 routes to port `8443`, while the `Gateway` listener stays on `8080`.
>
> **Task item 10:** The TLS `DestinationRule` names `partner.example.com`, and its `tls` block is under `portLevelSettings`, not at the top level.

Print the three fields:

```sh
kubectl -n egwtls-demo get gateway egress-gateway -o jsonpath='{.spec.servers[0].port.number} {.spec.servers[0].hosts}{"\n"}'
kubectl -n egwtls-demo get virtualservice partner-through-egress -o jsonpath='rule2 -> {.spec.http[1].route[0].destination.port.number}{"\n"}'
kubectl -n egwtls-demo get destinationrule originate-tls-for-partner -o jsonpath='host={.spec.host} top-level-tls=[{.spec.trafficPolicy.tls}] port-level={.spec.trafficPolicy.portLevelSettings[0].port.number} exportTo={.spec.exportTo}{"\n"}'
```

```text
8080 ["partner.example.com"]
rule2 -> 8443
host=partner.example.com top-level-tls=[] port-level=8443 exportTo=["istio-system"]
```

The gateway listens on `8080`, rule 2 sends to `8443`, and the `tls` block sits under `portLevelSettings` for port `8443`. The top-level `tls` is empty, so port `8080` of the host stays plain.

---

## Item 11: Check That Nothing Else Changed

> **Task item 11:** No Service exists in `outside-mesh`, and both the `tester` Deployment and the `partner-api` pod are running.

Run the same commands as in the start state:

```sh
kubectl -n outside-mesh get svc
kubectl -n egwtls-demo get deploy -o custom-columns=NAME:.metadata.name,READY:.status.readyReplicas,UID:.metadata.uid
kubectl -n outside-mesh get pods -o custom-columns=NAME:.metadata.name,PHASE:.status.phase,UID:.metadata.uid
```

```text
No resources found in outside-mesh namespace.
NAME     READY   UID
tester   1       1726d9ab-b9b5-45dc-836a-6739cbb176c0
NAME          PHASE     UID
partner-api   Running   58d1d6c3-3327-43c2-95bf-6cc85ec24ae2
```

The UIDs match the start state, so nothing was recreated. The partner is in the mesh only through the `ServiceEntry`.

---

## Submit

Send the setup for grading:

```sh
astrona submit -c sections/section-080/module-02/labs/lab-01
```

---

## Mistakes That Fail The Grader

- **Putting `tls` at the top level of `trafficPolicy`.** The call still works, but the grader checks that the `tls` block is under `portLevelSettings` for port `8443`.
- **Leaving out `exportTo: [istio-system]`.** The sidecar proxy of `tester` gets the TLS settings too, and the grader finds a `transportSocket` on it.
- **Naming the egress gateway Service in the TLS `DestinationRule`.** The TLS settings belong to the external host `partner.example.com`, because the gateway calls that host.
- **Sending rule 2 to port `8080`.** The partner only listens on `8443` with TLS, so the request gets `400` or a connection error.
- **Changing the `Gateway` listener to `8443` or `HTTPS`.** The listener receives plain HTTP from the client on `8080`.
- **Forgetting `insecureSkipVerify: true`.** The partner certificate is self-signed, and the gateway rejects it.
- **Creating a Service in `outside-mesh`.** The partner must be in the registry only through the `ServiceEntry`.
- **Testing too fast.** `kubectl apply` returns before `istiod` has pushed the configuration. If you still see the old status code, wait a few seconds and send the request again.
