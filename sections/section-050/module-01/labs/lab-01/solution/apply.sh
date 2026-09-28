#!/usr/bin/env bash
# Reference solution, applied only by `astrona test` (the `testing:` block).
# `astrona run` never runs this, so students still do the work themselves.
# Kept in step with solution.md - if one changes, change the other.
set -euo pipefail

kubectl apply -f - <<'EOF'
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: notification
  namespace: fault-demo
spec:
  hosts:
    - notification-service
  http:
    - match:
        - headers:
            end-user:
              exact: tester
      fault:
        delay:
          fixedDelay: 7s
          percentage:
            value: 100
        abort:
          httpStatus: 500
          percentage:
            value: 100
      route:
        - destination:
            host: notification-service
    - route:
        - destination:
            host: notification-service
EOF

kubectl apply -f - <<'EOF'
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: booking
  namespace: fault-demo
spec:
  hosts:
    - booking-service
  http:
    - timeout: 3s
      route:
        - destination:
            host: booking-service
EOF

# Give istiod time to push this configuration to every proxy before the grader
# reads it back. By hand you spend longer than this reading the apply output;
# `astrona test` applies and grades in the same second, and would otherwise
# measure the previous state.
sleep 15
