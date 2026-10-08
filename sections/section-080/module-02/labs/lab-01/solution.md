# Solution Walkthrough

Five objects, astronaut, combining almost every idea in the course. Build them in order, and the verification is three independent checks.

---

## Step 1: Understand the Two Constraints

```sh
PARTNER=$(cat /tmp/partner-ip); echo "partner: $PARTNER"
kubectl -n egwtls-demo exec deploy/tester -- \
  curl -s -o /dev/null -w 'plain to 8443: %{http_code}\n' --max-time 10 "http://$PARTNER:8443/"
kubectl -n egwtls-demo exec deploy/tester -- curl -sk --max-time 10 "https://$PARTNER:8443/"
kubectl -n istio-system logs deploy/istio-egressgateway --tail=-1 | grep -c partner || echo 0
```

```text
partner: 10.244.0.20
plain to 8443: 000
scheme=https
0
```

Two constraints and one starting fact: the partner planet refuses plaintext, it reports the scheme honestly, and the departure gate currently carries no signals.

---

## Step 2: Register the Host With Both Ports

```sh
PARTNER=$(cat /tmp/partner-ip)
cat > serviceentry-partner.yaml <<'EOF'
apiVersion: networking.istio.io/v1
kind: ServiceEntry
metadata:
  name: partner
  namespace: egwtls-demo
spec:
  hosts:
    - partner.example.com
  addresses:
    - $PARTNER
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
    - address: $PARTNER
EOF
kubectl apply -f serviceentry-partner.yaml
```

Port 8080 is where the sidecar's plaintext traffic arrives; 8443 is where stage 2 will send it. Both are needed.

---

## Step 3: The Gateway Listener And Its Subset

Write the manifest to a file and apply the file. It is the habit the exam rewards — you get something you can re-read, edit and re-apply, instead of a heredoc that is gone the moment it runs.

```sh
cat > egress-gateway-manifests.yaml <<'EOF'
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
---
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: egressgateway-for-partner
  namespace: egwtls-demo
spec:
  host: istio-egressgateway.istio-system.svc.cluster.local
  subsets:
    - name: partner
EOF
kubectl apply -f egress-gateway-manifests.yaml
```

The listener is on **8080** — the radio channel the gateway *receives* on. It will *send* on 8443. Those are two directions, and the apparent mismatch is the thing to get comfortable with.

---

## Step 4: The Two-Stage Route

```sh
cat > virtualservice-partner-through-egress.yaml <<'EOF'
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
EOF
kubectl apply -f virtualservice-partner-through-egress.yaml
```

Stage 2's `port: 8443` is the line that matters. Route it to 8080 and the gateway forwards plaintext to a TLS-only endpoint — a failure that looks like a TLS problem and is a routing one.

Test now, before the last object:

```sh
PARTNER=$(cat /tmp/partner-ip)
kubectl -n egwtls-demo exec deploy/tester -- \
  curl -s -o /dev/null -w 'without origination: %{http_code}\n' --max-time 20 "http://partner.example.com:8080/"
```

```text
without origination: 503
```

The signal reaches port 8443 — as plaintext. Each object has its own failure, and this is the one for a missing origination rule.

---

## Step 5: Originate TLS — On the External Host

```sh
cat > destinationrule-originate-tls-for-partner.yaml <<'EOF'
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: originate-tls-for-partner
  namespace: egwtls-demo
spec:
  # Scope the rule to the egress gateway's namespace. A DestinationRule for an
  # external host is visible mesh-wide by default, so every sidecar would also
  # originate TLS for it - the opposite of the point here, which is that the
  # sidecar speaks plain HTTP to the gateway and the gateway does the TLS.
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
EOF
kubectl apply -f destinationrule-originate-tls-for-partner.yaml
sleep 4
PARTNER=$(cat /tmp/partner-ip)
kubectl -n egwtls-demo exec deploy/tester -- curl -s --max-time 20 "http://partner.example.com:8080/"
```

```text
scheme=https
```

**`host: partner.example.com`** — the external host, not the gateway Service. Traffic policy is applied by whichever proxy is *calling* that host, and that is the gateway. Point it at `istio-egressgateway...` instead and nothing originates, because that is the policy for the sidecar's leg, which is plain HTTP by design.

This object is byte-for-byte what section 070 module 2 used. Only the proxy applying it has changed.

---

## Step 6: Three Independent Verifications

**The gateway was in the path, on port 8443:**

```sh
kubectl -n istio-system logs deploy/istio-egressgateway --tail=5 | grep partner.example.com | tail -1
```

```text
[2026-09-27T13:58:12.441Z] "GET / HTTP/1.1" 200 - via_upstream - "-" 0 14 5 4 "10.244.0.33" "curl/8.5.0" "..." "partner.example.com" "10.244.0.20:8443" outbound|8443||partner.example.com ...
```

A readable HTTP request, upstream on **8443**, cluster `outbound|8443||partner.example.com`.

**The TLS context is on the gateway and not the sidecar:**

```sh
echo -n "gateway: "
istioctl proxy-config cluster deploy/istio-egressgateway -n istio-system \
  --fqdn partner.example.com -o json | grep -c transportSocket
echo -n "sidecar: "
istioctl proxy-config cluster deploy/tester -n egwtls-demo \
  --fqdn partner.example.com -o json | grep -c transportSocket
```

```text
gateway: 1
sidecar: 0
```

One and zero — the most compact proof that policy follows the caller. In section 070 module 2 these same two commands give the opposite answer.

**The endpoint saw HTTPS:** `scheme=https` from step 5, reported by the server itself.

---

## Common Mistakes

- **The origination `DestinationRule` on the gateway Service.** Nothing originates — that is the sidecar's leg, which is plaintext by design.
- **Stage 2 routing to port 8080.** Plaintext to a TLS-only endpoint.
- **Declaring only port 8443 in the `ServiceEntry`.** Stage 2 has nowhere to start from.
- **`tls` at the top of `trafficPolicy`.** It would apply to 8080 as well.
- **Omitting `sni` or `insecureSkipVerify`.** The certificate names `partner.example.com` and is self-signed; both are needed here.
- **Confusing the two `DestinationRule` objects.** One names the gateway Service and holds an empty subset; the other names the external host and holds the TLS settings.
- **`mesh` missing from the top-level `gateways`.** Stage 1 never reaches sidecars and the call goes direct — which, on this endpoint, fails outright.
- **Counting gateway log lines without a baseline.** The log accumulates.
