#!/usr/bin/env bash
# Reference solution, applied only by `astrona test` (the `testing:` block).
# `astrona run` never runs this, so students still do the work themselves.
# Kept in step with solution.md - if one changes, change the other.
set -euo pipefail

kubectl apply -f - <<'EOF'
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: httpbin
  namespace: resilience-demo
spec:
  hosts:
    - httpbin
  http:
    - match:
        - method:
            exact: POST
      route:
        - destination:
            host: httpbin
            port:
              number: 8000
      timeout: 3s
      retries:
        attempts: 0
    - route:
        - destination:
            host: httpbin
            port:
              number: 8000
      timeout: 5s
      retries:
        attempts: 3
        perTryTimeout: 1s
        retryOn: gateway-error
EOF

# Give istiod time to push this configuration to every proxy before the grader
# reads it back. By hand you spend longer than this reading the apply output;
# `astrona test` applies and grades in the same second, and would otherwise
# measure the previous state.
sleep 15
