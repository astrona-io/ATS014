# Solution Walkthrough

You build eight objects for two external hosts and one egress gateway. Each host gets the same two-stage route through the egress gateway, and the secure host also gets a `DestinationRule` that starts TLS (Transport Layer Security) at the egress gateway.

---

## Step 1: Check the starting state

Read both IP addresses, call each server directly from `tester`, and count the egress gateway's access log lines for the partners:

```sh
PLAIN=$(cat /tmp/plain-ip); SECURE=$(cat /tmp/secure-ip)
echo "plain=$PLAIN  secure=$SECURE"
kubectl -n edge-egress exec deploy/tester -- \
  curl -s -o /dev/null -w 'plain direct:  %{http_code}\n' --max-time 10 "http://$PLAIN:8080/get"
kubectl -n edge-egress exec deploy/tester -- \
  curl -sk --max-time 10 "https://$SECURE:8443/"
kubectl -n istio-system logs deploy/istio-egressgateway --tail=-1 | grep -c partner.example || echo 0
```

```text
plain=10.244.0.21  secure=10.244.0.22
plain direct:  200
scheme=https
0
```

Both servers answer when called directly, and the egress gateway carries no traffic yet.

---

## Step 2: Add both hosts

Each `ServiceEntry` adds one external host to Istio's service registry and needs that host's IP address. Read both addresses into variables first:

```sh
PLAIN=$(cat /tmp/plain-ip); SECURE=$(cat /tmp/secure-ip)
```

Replace `<PLAIN>` and `<SECURE>` in the YAML below with the real addresses. To see them, run `echo $PLAIN` and `echo $SECURE`.

Save this as `serviceentry-plain.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: ServiceEntry
metadata:
  name: plain
  namespace: edge-egress
spec:
  hosts: [plain.partner.example]
  addresses: [<PLAIN>]
  ports:
    - { number: 8080, name: http, protocol: HTTP }
  location: MESH_EXTERNAL
  resolution: STATIC
  endpoints:
    - address: <PLAIN>
```

Apply it:

```sh
kubectl apply -f serviceentry-plain.yaml
```

Save this as `serviceentry-secure.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: ServiceEntry
metadata:
  name: secure
  namespace: edge-egress
spec:
  hosts: [secure.partner.example]
  addresses: [<SECURE>]
  ports:
    - { number: 8081, name: http,  protocol: HTTP }
    - { number: 8443, name: https, protocol: HTTPS }
  location: MESH_EXTERNAL
  resolution: STATIC
  endpoints:
    - address: <SECURE>
```

Apply it:

```sh
kubectl apply -f serviceentry-secure.yaml
```

The plain host needs one port. The secure host needs **two**: 8081, where the plain request from the sidecar proxy arrives, and 8443, where the egress gateway sends it on with TLS.

---

## Step 3: One `Gateway` with two listeners, and two subsets

The `Gateway` opens one listener per host on the egress gateway. Save this as `gateway-egress-gateway.yaml`:

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
    - port: { number: 8080, name: http-plain, protocol: HTTP }
      hosts: [plain.partner.example]
    - port: { number: 8081, name: http-secure, protocol: HTTP }
      hosts: [secure.partner.example]
```

Apply it:

```sh
kubectl apply -f gateway-egress-gateway.yaml
```

Each server names its own **external** host. A separate listener port per host keeps the two routes apart. The two server `name` values are different, which Istio requires.

Rule 1 of each `VirtualService` names a subset of the egress gateway's Service. Save this as `destinationrule-egressgateway-subsets.yaml`:

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

The two subsets have no labels, so they select the same pods. They exist so that each route uses its own Envoy cluster, which keeps the proxy configuration readable with two hosts on one egress gateway.

---

## Step 4: Partner A, plain HTTP for one workload

Save this as `virtualservice-plain-through-egress.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: plain-through-egress
  namespace: edge-egress
spec:
  hosts: [plain.partner.example]
  gateways: [mesh, egress-gateway]
  http:
    - match:
        - port: 8080
          sourceLabels:
            egress-allowed: "true"
      route:
        - destination:
            host: istio-egressgateway.istio-system.svc.cluster.local
            subset: plain
            port: { number: 8080 }
    - match:
        - gateways: [egress-gateway]
          port: 8080
      route:
        - destination:
            host: plain.partner.example
            port: { number: 8080 }
```

Apply it:

```sh
kubectl apply -f virtualservice-plain-through-egress.yaml
```

This is the usual two-stage route, with `sourceLabels` on rule 1. Only pods with the label `egress-allowed: "true"` get the route to the egress gateway.

---

## Step 5: Partner B, TLS at the egress gateway

Save this as `virtualservice-secure-through-egress.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: secure-through-egress
  namespace: edge-egress
spec:
  hosts: [secure.partner.example]
  gateways: [mesh, egress-gateway]
  http:
    - match:
        - gateways: [mesh]
          port: 8081
      route:
        - destination:
            host: istio-egressgateway.istio-system.svc.cluster.local
            subset: secure
            port: { number: 8081 }
    - match:
        - gateways: [egress-gateway]
          port: 8081
      route:
        - destination:
            host: secure.partner.example
            port: { number: 8443 }
```

Apply it:

```sh
kubectl apply -f virtualservice-secure-through-egress.yaml
```

Rule 2 sends to **8443**, while the listener stays on **8081**. One is the port the egress gateway receives on, the other the port it sends on.

Save this as `destinationrule-originate-tls-for-secure.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: originate-tls-for-secure
  namespace: edge-egress
spec:
  # Scope the rule to the egress gateway's namespace. A DestinationRule for an
  # external host is visible mesh-wide by default, so every sidecar would also
  # originate TLS for it - the opposite of the point here, which is that the
  # sidecar speaks plain HTTP to the gateway and the gateway does the TLS.
  exportTo:
    - istio-system
  host: secure.partner.example
  trafficPolicy:
    portLevelSettings:
      - port: { number: 8443 }
        tls:
          mode: SIMPLE
          sni: secure.partner.example
          insecureSkipVerify: true
```

Apply it:

```sh
kubectl apply -f destinationrule-originate-tls-for-secure.yaml
```

The rule names **`secure.partner.example`**, the external host. A `DestinationRule` is applied by the proxy that calls the host it names, and the egress gateway calls this host. A rule on the egress gateway Service would start no TLS toward the partner.

---

## Step 6: Check both routes

The loop below sends one request to each host from `tester` and prints how many lines the egress gateway logged for it:

```sh
for t in "plain plain.partner.example 8080 /get" "secure secure.partner.example 8081 /"; do
  set -- $t
  B=$(kubectl -n istio-system logs deploy/istio-egressgateway --tail=-1 | grep -c "$1.partner.example")
  printf '%-7s -> ' "$1"
  kubectl -n edge-egress exec deploy/tester -- \
    curl -s -w ' [%{http_code}]\n' --max-time 20 "http://$2:$3$4"
  sleep 3
  A=$(kubectl -n istio-system logs deploy/istio-egressgateway --tail=-1 | grep -c "$1.partner.example")
  echo "         gateway lines: +$((A - B))"
done
```

```text
plain   ->  [200]
         gateway lines: +1
secure  -> scheme=https
 [200]
         gateway lines: +1
```

Both hosts are reached through the one egress gateway, and the secure server reports `scheme=https` to a client that sent plain `http://`.

Then check the upstream port and where the TLS settings are:

```sh
kubectl -n istio-system logs deploy/istio-egressgateway --tail=20 | grep secure.partner.example | tail -1
echo -n "gateway transportSocket: "
istioctl proxy-config cluster deploy/istio-egressgateway -n istio-system --fqdn secure.partner.example -o json | grep -c transportSocket
echo -n "sidecar transportSocket: "
istioctl proxy-config cluster deploy/tester -n edge-egress --fqdn secure.partner.example -o json | grep -c transportSocket
```

You should see (log line shortened):

```text
[...] "GET / HTTP/1.1" 200 ... "secure.partner.example" "10.244.0.22:8443" outbound|8443||secure.partner.example ...
gateway transportSocket: 1
sidecar transportSocket: 0
```

---

## Step 7: Check the `sourceLabels` limit

Send the plain request from `other-client`, which does not carry `egress-allowed: "true"`, and count the egress gateway's lines before and after:

```sh
B=$(kubectl -n istio-system logs deploy/istio-egressgateway --tail=-1 | grep -c plain.partner.example)
kubectl -n edge-egress exec deploy/other-client -- \
  curl -s -o /dev/null -w 'other-client: %{http_code}\n' --max-time 20 "http://plain.partner.example:8080/get"
sleep 3
A=$(kubectl -n istio-system logs deploy/istio-egressgateway --tail=-1 | grep -c plain.partner.example)
echo "gateway lines: +$((A - B))"
```

```text
other-client: 200
gateway lines: +0
```

`other-client` reached the server directly, without the egress gateway. `sourceLabels` limits which workloads get a route; it does not block the others.

---

## Common mistakes

- **The TLS `DestinationRule` on the egress gateway Service.** Nothing starts TLS toward the partner.
- **Rule 2 for the secure host routes to 8081.** The egress gateway sends plain text to a server that only speaks TLS.
- **One listener for both hosts.** It can work, but the task asks for two so the routes stay apart, and Istio rejects duplicate server `name` values.
- **Only one subset.** Both routes then share one cluster, and the proxy configuration is harder to read.
- **`mesh` missing from either top-level `gateways`.** That route never reaches the sidecar proxies.
- **`sourceLabels` on the secure route.** The task puts it only on the plain route.
- **Expecting `other-client` to be blocked.** It is not routed through the egress gateway, but it is not denied.
- **Counting the egress gateway's log lines without a starting count.** The log keeps growing for both partners, so compare before and after.
