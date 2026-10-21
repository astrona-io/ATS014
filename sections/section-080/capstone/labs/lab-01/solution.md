# Solution Walkthrough

The walkthrough follows the task. Items 1 to 4 build partner A (plain HTTP through the egress gateway, for one workload only). Items 5 to 7 build partner B (TLS started at the egress gateway). Items 8 to 13 are the grader checks, and the walkthrough proves each one with real requests after the objects exist. Each section ends with a check.

The outputs below come from a real run. Your pod addresses, timestamps and UIDs differ.

---

## Start: Look At The Starting State

Read both addresses of the partner servers. Call `plain-api` directly, call `secure-api` once with plain text and once with TLS, and count the lines for the partners in the egress gateway access log:

```sh
PLAIN=$(cat /tmp/plain-ip); SECURE=$(cat /tmp/secure-ip)
echo "plain=$PLAIN secure=$SECURE"
kubectl -n edge-egress exec deploy/tester -- curl -s -o /dev/null -w 'plain direct: %{http_code}\n' --max-time 10 http://$PLAIN:8080/get
kubectl -n edge-egress exec deploy/tester -- curl -s -o /dev/null -w 'secure plain-text to 8443: %{http_code}\n' --max-time 10 http://$SECURE:8443/
kubectl -n edge-egress exec deploy/tester -- curl -sk --max-time 10 https://$SECURE:8443/
kubectl -n istio-system logs deploy/istio-egressgateway --tail=-1 | grep -c partner.example
```

```text
plain=10.244.0.8 secure=10.244.0.9
plain direct: 200
secure plain-text to 8443: 400
scheme=https
0
```

`plain-api` answers plain HTTP. `secure-api` rejects plain text with `400` and answers TLS with `scheme=https`. The egress gateway logged nothing yet.

Check that no Istio object exists, and save the state that item 13 says must stay the same:

```sh
kubectl -n edge-egress get serviceentry,gateway,destinationrule,virtualservice
kubectl -n outside-mesh get svc
kubectl -n edge-egress get deploy -o custom-columns=NAME:.metadata.name,READY:.status.readyReplicas,UID:.metadata.uid
kubectl -n outside-mesh get pods -o custom-columns=NAME:.metadata.name,PHASE:.status.phase,UID:.metadata.uid
kubectl -n istio-system get deploy istio-egressgateway -o jsonpath='egress deploy uid={.metadata.uid}{"\n"}'
```

```text
No resources found in edge-egress namespace.
No resources found in outside-mesh namespace.
NAME           READY   UID
other-client   1       790bd163-a37b-40a9-8c2b-9056dde576c6
tester         1       0c584206-a810-4f43-8908-6b6a10af573c
NAME         PHASE     UID
plain-api    Running   95a6ba32-547e-422e-a7a8-4d0df51fd782
secure-api   Running   6621b023-d60b-46c6-8cb9-260d59f3cbf0
egress deploy uid=193b4a3e-e729-47bd-8b69-86e2e5cfc811
```

---

## Item 1: Add The Plain Partner To The Service Registry

> **Task item 1:** A `ServiceEntry` named `plain` for `plain.partner.example`: the `plain-api` address in `spec.addresses`, port `8080` named `http` with protocol `HTTP`, `MESH_EXTERNAL`, `STATIC`, and an `endpoints` entry for that address.

A `ServiceEntry` adds a host to the service registry, the list of hosts and endpoints that `istiod` knows about. Replace `<PLAIN>` in both places with the address that `echo $PLAIN` prints. Save this as `serviceentry-plain.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: ServiceEntry
metadata:
  name: plain
  namespace: edge-egress
spec:
  hosts:
    - plain.partner.example
  addresses:
    - <PLAIN>
  ports:
    - number: 8080
      name: http
      protocol: HTTP
  location: MESH_EXTERNAL
  resolution: STATIC
  endpoints:
    - address: <PLAIN>
```

Apply it:

```sh
kubectl apply -f serviceentry-plain.yaml
```

Then check the result:

```sh
kubectl -n edge-egress get serviceentry plain -o jsonpath='{.spec}{"\n"}'
```

```text
{"addresses":["10.244.0.8"],"endpoints":[{"address":"10.244.0.8"}],"hosts":["plain.partner.example"],"location":"MESH_EXTERNAL","ports":[{"name":"http","number":8080,"protocol":"HTTP"}],"resolution":"STATIC"}
```

---

## Item 2: Open Two Listeners On The Egress Gateway

> **Task item 2:** A `Gateway` named `egress-gateway` that selects `istio: egressgateway`, with two servers: port `8080` `HTTP` for `plain.partner.example`, and port `8081` `HTTP` for `secure.partner.example`.

A `Gateway` configures the listeners of a gateway proxy. One listener port for each host keeps the two routes apart. The two servers need different `name` values, which Istio requires. Save this as `gateway-egress-gateway.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: Gateway
metadata:
  name: egress-gateway
  namespace: edge-egress
spec:
  selector:
    istio: egressgateway
  servers:
    - port:
        number: 8080
        name: http-plain
        protocol: HTTP
      hosts:
        - plain.partner.example
    - port:
        number: 8081
        name: http-secure
        protocol: HTTP
      hosts:
        - secure.partner.example
```

Apply it:

```sh
kubectl apply -f gateway-egress-gateway.yaml
```

Then check the result:

```sh
kubectl -n edge-egress get gateway egress-gateway -o jsonpath='{range .spec.servers[*]}{.port.number}{" "}{.port.name}{" "}{.port.protocol}{" "}{.hosts}{"\n"}{end}'
```

```text
8080 http-plain HTTP ["plain.partner.example"]
8081 http-secure HTTP ["secure.partner.example"]
```

---

## Item 3: Add Two Subsets For The Egress Gateway

> **Task item 3:** A `DestinationRule` named `egressgateway-subsets` for `istio-egressgateway.istio-system.svc.cluster.local` with two subsets, `plain` and `secure`, both without labels.

A subset is a named group of pods. These two have no labels, so they select the same pods. They exist so that each route uses its own Envoy cluster. Save this as `destinationrule-egressgateway-subsets.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: egressgateway-subsets
  namespace: edge-egress
spec:
  host: istio-egressgateway.istio-system.svc.cluster.local
  subsets:
    - name: plain
    - name: secure
```

Apply it:

```sh
kubectl apply -f destinationrule-egressgateway-subsets.yaml
```

Then check the result:

```sh
kubectl -n edge-egress get destinationrule egressgateway-subsets -o jsonpath='{.spec}{"\n"}'
```

```text
{"host":"istio-egressgateway.istio-system.svc.cluster.local","subsets":[{"name":"plain"},{"name":"secure"}]}
```

---

## Item 4: Route The Plain Partner Through The Egress Gateway

> **Task item 4:** A `VirtualService` named `plain-through-egress` for `plain.partner.example`, with the top-level gateways `mesh` and `egress-gateway`. Rule 1 matches port `8080` and `sourceLabels: {egress-allowed: "true"}`, with no `gateways` in the match, and routes to the egress gateway Service, subset `plain`, port `8080`. Rule 2: `gateways: [egress-gateway]`, port `8080`, routes to `plain.partner.example` port `8080`.

A `VirtualService` sets how requests to a host are routed. Rule 1 is read by the sidecar proxies. The label `egress-allowed: "true"` limits it to pods that carry that label. Do not add `gateways: [mesh]` to rule 1. On Istio 1.30.5, that combination makes Istio ignore the label, and every sidecar proxy gets the route. Rule 2 is read by the egress gateway and sends the request on to the partner. Save this as `virtualservice-plain-through-egress.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: plain-through-egress
  namespace: edge-egress
spec:
  hosts:
    - plain.partner.example
  gateways:
    - mesh
    - egress-gateway
  http:
    - match:
        - port: 8080
          sourceLabels:
            egress-allowed: "true"
      route:
        - destination:
            host: istio-egressgateway.istio-system.svc.cluster.local
            subset: plain
            port:
              number: 8080
    - match:
        - gateways: [egress-gateway]
          port: 8080
      route:
        - destination:
            host: plain.partner.example
            port:
              number: 8080
```

Apply it:

```sh
kubectl apply -f virtualservice-plain-through-egress.yaml
```

Then check the result:

```sh
kubectl -n edge-egress get virtualservice plain-through-egress -o jsonpath='gateways={.spec.gateways}{"\n"}{range .spec.http[*]}{.match}{" -> "}{.route[0].destination.host}{" "}{.route[0].destination.subset}{":"}{.route[0].destination.port.number}{"\n"}{end}'
```

```text
gateways=["mesh","egress-gateway"]
[{"port":8080,"sourceLabels":{"egress-allowed":"true"}}] -> istio-egressgateway.istio-system.svc.cluster.local plain:8080
[{"gateways":["egress-gateway"],"port":8080}] -> plain.partner.example :8080
```

---

## Item 5: Add The Secure Partner To The Service Registry

> **Task item 5:** A `ServiceEntry` named `secure` for `secure.partner.example`: the `secure-api` address in `spec.addresses`, two ports (`8081` `http` `HTTP`, and `8443` `https` `HTTPS`), `MESH_EXTERNAL`, `STATIC`, and an `endpoints` entry for that address.

The secure host has two ports. Port `8081` is where the plain request from the sidecar proxy arrives. Port `8443` is where the egress gateway sends it on with TLS. Replace `<SECURE>` in both places with the address that `echo $SECURE` prints. Save this as `serviceentry-secure.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: ServiceEntry
metadata:
  name: secure
  namespace: edge-egress
spec:
  hosts:
    - secure.partner.example
  addresses:
    - <SECURE>
  ports:
    - number: 8081
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
kubectl apply -f serviceentry-secure.yaml
```

Then check the result:

```sh
kubectl -n edge-egress get serviceentry secure -o jsonpath='{.spec}{"\n"}'
```

```text
{"addresses":["10.244.0.9"],"endpoints":[{"address":"10.244.0.9"}],"hosts":["secure.partner.example"],"location":"MESH_EXTERNAL","ports":[{"name":"http","number":8081,"protocol":"HTTP"},{"name":"https","number":8443,"protocol":"HTTPS"}],"resolution":"STATIC"}
```

---

## Item 6: Route The Secure Partner Through The Egress Gateway

> **Task item 6:** A `VirtualService` named `secure-through-egress` for `secure.partner.example`, with the top-level gateways `mesh` and `egress-gateway`. Rule 1: `gateways: [mesh]`, port `8081`, to the egress gateway Service, subset `secure`, port `8081`. Rule 2: `gateways: [egress-gateway]`, port `8081`, to `secure.partner.example` port `8443`.

Rule 2 receives on `8081`, the port of the `Gateway` listener, and sends on to `8443`. Save this as `virtualservice-secure-through-egress.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: secure-through-egress
  namespace: edge-egress
spec:
  hosts:
    - secure.partner.example
  gateways:
    - mesh
    - egress-gateway
  http:
    - match:
        - gateways: [mesh]
          port: 8081
      route:
        - destination:
            host: istio-egressgateway.istio-system.svc.cluster.local
            subset: secure
            port:
              number: 8081
    - match:
        - gateways: [egress-gateway]
          port: 8081
      route:
        - destination:
            host: secure.partner.example
            port:
              number: 8443
```

Apply it:

```sh
kubectl apply -f virtualservice-secure-through-egress.yaml
```

Then check the result, and send one request. Nothing starts TLS yet:

```sh
kubectl -n edge-egress get virtualservice secure-through-egress -o jsonpath='gateways={.spec.gateways}{"\n"}{range .spec.http[*]}{.match}{" -> "}{.route[0].destination.host}{" "}{.route[0].destination.subset}{":"}{.route[0].destination.port.number}{"\n"}{end}'
kubectl -n edge-egress exec deploy/tester -- curl -s -o /dev/null -w 'secure without origination: %{http_code}\n' --max-time 20 http://secure.partner.example:8081/
```

```text
gateways=["mesh","egress-gateway"]
[{"gateways":["mesh"],"port":8081}] -> istio-egressgateway.istio-system.svc.cluster.local secure:8081
[{"gateways":["egress-gateway"],"port":8081}] -> secure.partner.example :8443
secure without origination: 400
```

The request now passes through the egress gateway, but the gateway sends plain text to port `8443`, and the partner rejects it with `400`. Item 7 fixes this.

---

## Item 7: Start TLS At The Egress Gateway

> **Task item 7:** A `DestinationRule` named `originate-tls-for-secure` for `secure.partner.example`, with `portLevelSettings` for port `8443`: `tls.mode: SIMPLE`, `tls.sni: secure.partner.example`, `insecureSkipVerify: true`, and `exportTo: [istio-system]`.

A `DestinationRule` is applied by the proxy that calls the host. Here that is the egress gateway, which runs in `istio-system`. With `exportTo: [istio-system]`, only proxies in that namespace get the rule, so the sidecar proxies keep a plain cluster. Save this as `destinationrule-originate-tls-for-secure.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: originate-tls-for-secure
  namespace: edge-egress
spec:
  exportTo:
    - istio-system
  host: secure.partner.example
  trafficPolicy:
    portLevelSettings:
      - port:
          number: 8443
        tls:
          mode: SIMPLE
          sni: secure.partner.example
          insecureSkipVerify: true
```

Apply it:

```sh
kubectl apply -f destinationrule-originate-tls-for-secure.yaml
```

Then check the result and run the analyzer:

```sh
kubectl -n edge-egress get destinationrule originate-tls-for-secure -o jsonpath='{.spec}{"\n"}'
istioctl analyze -n edge-egress
```

```text
{"exportTo":["istio-system"],"host":"secure.partner.example","trafficPolicy":{"portLevelSettings":[{"port":{"number":8443},"tls":{"insecureSkipVerify":true,"mode":"SIMPLE","sni":"secure.partner.example"}}]}}
Warning [IST0129] (DestinationRule edge-egress/originate-tls-for-secure) DestinationRule edge-egress/originate-tls-for-secure in namespace edge-egress has TLS mode set to SIMPLE but no caCertificates are set to validate server identity for host: secure.partner.example at port number:8443
```

The warning is expected. The task asks for `insecureSkipVerify: true` because the partner certificate is self-signed, so the gateway has no certificate authority to verify it.

---

## Item 8: Reach The Plain Partner From `tester`

> **Task item 8:** From `tester`: `GET http://plain.partner.example:8080/get` returns `200`, and the egress gateway logs it.

Send the request. The first command keeps only the last lines of the response body (shortened). Then wait for the log and count the gateway lines for the plain host before and after:

```sh
kubectl -n istio-system logs deploy/istio-egressgateway --tail=-1 | grep -c plain.partner.example
kubectl -n edge-egress exec deploy/tester -- curl -s -w '\nstatus: %{http_code}\n' --max-time 20 http://plain.partner.example:8080/get | tail -3
sleep 4
kubectl -n istio-system logs deploy/istio-egressgateway --tail=-1 | grep -c plain.partner.example
```

```text
}

status: 200
```

The status is `200`. The two counts differ by exactly one: the real run logged `+1` line for this request. The sidecar proxy of `tester` has the label `egress-allowed: "true"`, so it sent the request to the egress gateway.

---

## Item 9: Reach The Secure Partner From `tester`

> **Task item 9:** From `tester`: `GET http://secure.partner.example:8081/` returns `200` with the body `scheme=https`, and the egress gateway logs it with an upstream on `8443`.

Send a plain `http://` request, wait, and read the last gateway line for the secure host (cut to 300 characters):

```sh
kubectl -n edge-egress exec deploy/tester -- curl -s -w '\nstatus: %{http_code}\n' --max-time 20 http://secure.partner.example:8081/
sleep 4
kubectl -n istio-system logs deploy/istio-egressgateway --tail=20 | grep secure.partner.example | tail -1 | cut -c1-300
```

```text
scheme=https

status: 200
[2026-10-20T23:27:01.653Z] "GET / HTTP/1.1" 200 - via_upstream - "-" 0 13 3 2 "10.244.0.11" "curl/8.23.0" "3813e49e-8db7-9053-ac4a-8c924f5c6941" "secure.partner.example:8081" "10.244.0.9:8443" outbound|8443||secure.partner.example 10.244.0.6:34126 10.244.0.6:8081 10.244.0.11:60208 - -
```

The client sent plain HTTP to port `8081`, and the partner reports `scheme=https`. The gateway received the request on `:8081` and called the upstream `10.244.0.9:8443`.

---

## Item 10: Check The `sourceLabels` Limit

> **Task item 10:** From `other-client`: the plain call still returns `200`, but the egress gateway logs no line for it.

`other-client` does not carry `egress-allowed: "true"`. Send the plain request from it, and compare the gateway lines before and after:

```sh
kubectl -n istio-system logs deploy/istio-egressgateway --tail=-1 | grep -c plain.partner.example
kubectl -n edge-egress exec deploy/other-client -- curl -s -o /dev/null -w 'other-client: %{http_code}\n' --max-time 20 http://plain.partner.example:8080/get
sleep 4
kubectl -n istio-system logs deploy/istio-egressgateway --tail=-1 | grep -c plain.partner.example
```

```text
other-client: 200
```

The status is `200`, and the two counts are equal: the real run logged `+0` lines. `other-client` reached the server directly, with no egress gateway. `sourceLabels` limits which workloads get the route through the egress gateway. It does not block the others.

---

## Item 11: Compare The TLS Settings Of Two Proxies

> **Task item 11:** The egress gateway has a TLS `transportSocket` in its cluster for `secure.partner.example`; the `tester` sidecar proxy does not.

A `transportSocket` is the part of an Envoy cluster that holds its TLS settings. Count it in both proxies:

```sh
echo -n "gateway: "; istioctl proxy-config cluster deploy/istio-egressgateway -n istio-system --fqdn secure.partner.example -o json | grep -c transportSocket
echo -n "tester: "; istioctl proxy-config cluster deploy/tester -n edge-egress --fqdn secure.partner.example -o json | grep -c transportSocket
```

```text
gateway: 1
tester: 0
```

This is the effect of `exportTo: [istio-system]`. Without it, the sidecar proxy would also try TLS toward a gateway that expects plain HTTP.

---

## Item 12: Check Where The TLS Block Sits

> **Task item 12:** The TLS `DestinationRule` names `secure.partner.example` and keeps its `tls` block under `portLevelSettings`, not at the top level.

Print the host, the top-level `tls` and the port of the port-level setting:

```sh
kubectl -n edge-egress get destinationrule originate-tls-for-secure -o jsonpath='host={.spec.host} top-level-tls=[{.spec.trafficPolicy.tls}] port-level={.spec.trafficPolicy.portLevelSettings[0].port.number} exportTo={.spec.exportTo}{"\n"}'
```

```text
host=secure.partner.example top-level-tls=[] port-level=8443 exportTo=["istio-system"]
```

The top-level `tls` is empty, so any other port of the host stays plain.

---

## Item 13: Check That Nothing Else Changed

> **Task item 13:** Both hosts are carried by the same egress gateway Deployment, and no Service exists in `outside-mesh`.

Run the commands of the start state again:

```sh
kubectl -n outside-mesh get svc
kubectl -n istio-system get deploy istio-egressgateway -o jsonpath='egress deploy uid={.metadata.uid}{"\n"}'
kubectl -n edge-egress get deploy -o custom-columns=NAME:.metadata.name,READY:.status.readyReplicas,UID:.metadata.uid
kubectl -n outside-mesh get pods -o custom-columns=NAME:.metadata.name,PHASE:.status.phase,UID:.metadata.uid
```

```text
No resources found in outside-mesh namespace.
egress deploy uid=193b4a3e-e729-47bd-8b69-86e2e5cfc811
NAME           READY   UID
other-client   1       790bd163-a37b-40a9-8c2b-9056dde576c6
tester         1       0c584206-a810-4f43-8908-6b6a10af573c
NAME         PHASE     UID
plain-api    Running   95a6ba32-547e-422e-a7a8-4d0df51fd782
secure-api   Running   6621b023-d60b-46c6-8cb9-260d59f3cbf0
```

All UIDs match the start state. Both hosts use the one `istio-egressgateway` Deployment, and the partners are in the mesh only through the `ServiceEntry` objects.

---

## Submit

Send the setup for grading:

```sh
astrona submit -c sections/section-080/capstone/labs/lab-01
```

---

## Mistakes That Fail The Grader

- **Putting the TLS `DestinationRule` on the egress gateway Service (items 7 and 11).** The gateway calls the external host, so the rule must name `secure.partner.example`. Otherwise nothing starts TLS toward the partner.
- **Sending rule 2 of the secure host to `8081` (items 6 and 9).** The egress gateway then sends plain text to a server that only speaks TLS and gets `400`.
- **Using one listener for both hosts (item 2).** The task asks for two listener ports, and Istio rejects duplicate server `name` values.
- **Adding only one subset (item 3).** The grader checks that both `plain` and `secure` exist.
- **Leaving `mesh` out of a top-level `gateways` list (items 4 and 6).** The route never reaches the sidecar proxies.
- **Adding `gateways: [mesh]` to rule 1 of the plain route (items 4, 8 and 10).** On Istio 1.30.5, Istio ignores `sourceLabels` then, and `other-client` is routed through the egress gateway too.
- **Adding `sourceLabels` to the secure route (items 6 and 9).** The task puts it only on the plain route.
- **Leaving out `exportTo: [istio-system]` (items 7 and 11).** The `tester` sidecar proxy gets a `transportSocket`.
- **Putting `tls` at the top level of `trafficPolicy` (item 12).** The grader checks `portLevelSettings`.
- **Expecting `other-client` to be blocked (item 10).** It is not routed through the egress gateway, but it is not denied.
- **Creating a Service in `outside-mesh` (item 13).** That registers the endpoints in a second way, and the grader rejects it.
- **Counting the gateway log lines without a starting count (items 8 to 10).** The log keeps growing for both partners, so compare before and after.
