# Solution Walkthrough

Eight objects, two partners, one gateway. The structure is module 1's chain twice over, with module 2's origination added to the second one.

---

## Step 1: Establish the Baseline

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

Both endpoints reachable directly, the gateway carrying nothing.

---

## Step 2: Register Both Hosts

```sh
PLAIN=$(cat /tmp/plain-ip); SECURE=$(cat /tmp/secure-ip)
kubectl apply -f - <<EOF
apiVersion: networking.istio.io/v1
kind: ServiceEntry
metadata:
  name: plain
  namespace: edge-egress
spec:
  hosts: [plain.partner.example]
  addresses: [$PLAIN]
  ports:
    - { number: 8080, name: http, protocol: HTTP }
  location: MESH_EXTERNAL
  resolution: STATIC
  endpoints:
    - address: $PLAIN
---
apiVersion: networking.istio.io/v1
kind: ServiceEntry
metadata:
  name: secure
  namespace: edge-egress
spec:
  hosts: [secure.partner.example]
  addresses: [$SECURE]
  ports:
    - { number: 8081, name: http,  protocol: HTTP }
    - { number: 8443, name: https, protocol: HTTPS }
  location: MESH_EXTERNAL
  resolution: STATIC
  endpoints:
    - address: $SECURE
EOF
```

The plain host needs one port; the secure host needs **two** — 8081 where the sidecar's plaintext arrives, 8443 where the gateway will send it.

---

## Step 3: One Gateway, Two Listeners, Two Subsets

```sh
kubectl apply -f - <<'EOF'
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
---
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
EOF
```

One `Gateway` with two servers, each naming its own **external** hostname. A separate listener port per host keeps the two chains distinguishable — and note both server `name` values are unique, which Istio requires.

Two label-less subsets, one per partner. They narrow nothing; they exist so each chain names a distinct cluster and the proxy configuration stays readable with two partners on one gateway.

---

## Step 4: Partner A — Plain, Restricted

```sh
kubectl apply -f - <<'EOF'
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
EOF
```

Module 1's chain exactly, with `sourceLabels` on stage 1.

---

## Step 5: Partner B — TLS At The Gateway

```sh
kubectl apply -f - <<'EOF'
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
---
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
EOF
```

Stage 2 goes to **8443** while the listener stays on **8081** — receive port and send port, two directions.

The origination rule names **`secure.partner.example`**, the external host. The gateway is the proxy calling it, so that is where the policy takes effect. Pointing it at the gateway Service would originate nothing.

---

## Step 6: Verify Both Chains

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

Both partners through the one gateway, and the secure one reporting `scheme=https` to a plain `http://` caller.

Confirm the upstream port and the TLS placement:

```sh
kubectl -n istio-system logs deploy/istio-egressgateway --tail=20 | grep secure.partner.example | tail -1
echo -n "gateway transportSocket: "
istioctl proxy-config cluster deploy/istio-egressgateway -n istio-system --fqdn secure.partner.example -o json | grep -c transportSocket
echo -n "sidecar transportSocket: "
istioctl proxy-config cluster deploy/tester -n edge-egress --fqdn secure.partner.example -o json | grep -c transportSocket
```

```text
[...] "GET / HTTP/1.1" 200 ... "secure.partner.example" "10.244.0.22:8443" outbound|8443||secure.partner.example ...
gateway transportSocket: 1
sidecar transportSocket: 0
```

---

## Step 7: Verify The Restriction

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

Reached the endpoint, bypassed the gateway. `sourceLabels` narrowed the route, not the permission — which is the distinction to carry out of this section.

---

## Common Mistakes

- **The origination `DestinationRule` on the gateway Service.** Nothing originates.
- **Stage 2 for the secure host routing to 8081.** Plaintext to a TLS-only endpoint.
- **One listener for both hosts.** Workable, but the task asks for two so the chains stay distinguishable — and duplicate server `name` values are rejected.
- **Only one subset.** Both chains would share a cluster and the proxy config becomes ambiguous.
- **`mesh` missing from either top-level `gateways`.** That chain never diverts.
- **`sourceLabels` on the secure chain.** The task puts it only on the plain one.
- **Expecting `other-client` to be blocked.** It is un-diverted, not denied.
- **Counting gateway log lines without a baseline.** The log accumulates across both partners.
