#!/usr/bin/env bash
# Reference solution, applied only by `astrona test` (the `testing:` block).
# `astrona run` never runs this, so students still do the work themselves.
# Kept in step with solution.md - if one changes, change the other.
set -euo pipefail

kubectl apply -f - <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: shared-gateway
  namespace: gwapi-demo
  annotations:
    # kind has no load balancer, so the Service Istio creates for this Gateway
    # would sit at EXTERNAL-IP <pending> for ever and the Gateway would report
    # Programmed=False / AddressNotAssigned. Asking for a ClusterIP gives it an
    # address it can actually be programmed with.
    networking.istio.io/service-type: ClusterIP
spec:
  gatewayClassName: istio
  listeners:
    - name: http
      port: 80
      protocol: HTTP
      allowedRoutes:
        namespaces:
          from: Selector
          selector:
            matchLabels:
              gateway-access: "true"
EOF
kubectl -n gwapi-demo rollout status deployment shared-gateway-istio --timeout=120s

kubectl label namespace gwapi-team gateway-access=true

kubectl apply -f - <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: booking
  namespace: gwapi-demo
spec:
  parentRefs:
    - name: shared-gateway
  hostnames:
    - booking.ica.local
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /book
      backendRefs:
        - name: booking-service
          port: 80
EOF

kubectl apply -f - <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: catalog
  namespace: gwapi-team
spec:
  parentRefs:
    - name: shared-gateway
      namespace: gwapi-demo
  hostnames:
    - catalog.ica.local
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /items
      backendRefs:
        - name: catalog-service
          port: 80
EOF

# Give istiod time to push this configuration to every proxy before the grader
# reads it back. By hand you spend longer than this reading the apply output;
# `astrona test` applies and grades in the same second, and would otherwise
# measure the previous state.
sleep 15
