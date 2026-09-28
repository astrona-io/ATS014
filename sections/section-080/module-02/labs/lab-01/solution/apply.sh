#!/usr/bin/env bash
# Reference solution, applied only by `astrona test` (the `testing:` block).
# `astrona run` never runs this, so students still do the work themselves.
# Kept in step with solution.md - if one changes, change the other.
set -euo pipefail

PARTNER=$(cat /tmp/partner-ip)
kubectl apply -f - <<EOF
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

kubectl apply -f - <<'EOF'
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

kubectl apply -f - <<'EOF'
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

kubectl apply -f - <<'EOF'
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
sleep 4
PARTNER=$(cat /tmp/partner-ip)

# Give istiod time to push this configuration to every proxy before the grader
# reads it back. By hand you spend longer than this reading the apply output;
# `astrona test` applies and grades in the same second, and would otherwise
# measure the previous state.
sleep 15
