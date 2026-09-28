#!/usr/bin/env bash
# Reference solution, applied only by `astrona test` (the `testing:` block).
# `astrona run` never runs this, so students still do the work themselves.
# Kept in step with solution.md - if one changes, change the other.
set -euo pipefail

kubectl apply -f - <<'EOF'
apiVersion: networking.istio.io/v1
kind: Gateway
metadata:
  name: native-gw
  namespace: edge
spec:
  selector:
    istio: ingressgateway
  servers:
    - port:
        number: 80
        name: http
        protocol: HTTP
      hosts:
        - native.ica.local
---
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: native
  namespace: edge
spec:
  hosts:
    - native.ica.local
  gateways:
    - native-gw
  http:
    - match:
        - uri:
            prefix: /api
      route:
        - destination:
            host: native-app
            port:
              number: 80
EOF

kubectl apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  name: istio
spec:
  controller: istio.io/ingress-controller
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: legacy
  namespace: edge
spec:
  ingressClassName: istio
  tls:
    - hosts:
        - legacy.ica.local
      secretName: legacy-credential
  rules:
    - host: legacy.ica.local
      http:
        paths:
          - path: /api
            pathType: Prefix
            backend:
              service:
                name: legacy-app
                port:
                  number: 80
EOF

kubectl -n istio-system create secret tls legacy-credential \
  --key=/tmp/legacy.key --cert=/tmp/legacy.crt

kubectl apply -f - <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: modern-gw
  namespace: edge
spec:
  gatewayClassName: istio
  listeners:
    - name: http
      port: 80
      protocol: HTTP
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: modern
  namespace: edge
spec:
  parentRefs:
    - name: modern-gw
  hostnames:
    - modern.ica.local
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /api
      backendRefs:
        - name: modern-app
          port: 80
EOF
kubectl -n edge rollout status deployment modern-gw-istio --timeout=120s

# Give istiod time to push this configuration to every proxy before the grader
# reads it back. By hand you spend longer than this reading the apply output;
# `astrona test` applies and grades in the same second, and would otherwise
# measure the previous state.
sleep 15
