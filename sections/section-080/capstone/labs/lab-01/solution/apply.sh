#!/usr/bin/env bash
# Reference solution, applied only by `astrona test` (the `testing:` block).
# `astrona run` never runs this, so students still do the work themselves.
# Kept in step with solution.md - if one changes, change the other.
set -euo pipefail

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
  host: secure.partner.example
  trafficPolicy:
    portLevelSettings:
      - port: { number: 8443 }
        tls:
          mode: SIMPLE
          sni: secure.partner.example
          insecureSkipVerify: true
EOF

# Give istiod time to push this configuration to every proxy before the grader
# reads it back. By hand you spend longer than this reading the apply output;
# `astrona test` applies and grades in the same second, and would otherwise
# measure the previous state.
sleep 15
