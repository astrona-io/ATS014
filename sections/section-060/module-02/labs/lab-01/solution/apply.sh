#!/usr/bin/env bash
# Reference solution, applied only by `astrona test` (the `testing:` block).
# `astrona run` never runs this, so students still do the work themselves.
# Kept in step with solution.md - if one changes, change the other.
set -euo pipefail

kubectl apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  name: istio
spec:
  controller: istio.io/ingress-controller
EOF

kubectl apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: booking
  namespace: k8s-ingress-demo
spec:
  ingressClassName: istio
  tls:
    - hosts:
        - booking.ica.local
      secretName: booking-credential
  rules:
    - host: booking.ica.local
      http:
        paths:
          - path: /book
            pathType: Prefix
            backend:
              service:
                name: booking-service
                port:
                  number: 80
          - path: /status/200
            pathType: Exact
            backend:
              service:
                name: booking-service
                port:
                  number: 80
EOF

kubectl -n istio-system create secret tls booking-credential \
  --key=/tmp/booking.key --cert=/tmp/booking.crt

# Give istiod time to push this configuration to every proxy before the grader
# reads it back. By hand you spend longer than this reading the apply output;
# `astrona test` applies and grades in the same second, and would otherwise
# measure the previous state.
sleep 15
