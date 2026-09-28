#!/usr/bin/env bash
# Reference solution, applied only by `astrona test` (the `testing:` block).
# `astrona run` never runs this, so students still do the work themselves.
# Kept in step with solution.md - if one changes, change the other.
set -euo pipefail

kubectl apply -f - <<'EOF'
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: ledger
  namespace: payments
spec:
  hosts:
    - ledger
  http:
    - match:
        - method:
            exact: POST
      route:
        - destination:
            host: ledger
            port:
              number: 8000
      timeout: 3s
      retries:
        attempts: 0
    - route:
        - destination:
            host: ledger
            port:
              number: 8000
      timeout: 4s
      retries:
        attempts: 2
        perTryTimeout: 1s
        retryOn: gateway-error
EOF

kubectl apply -f - <<'EOF'
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: ledger
  namespace: payments
spec:
  host: ledger
  trafficPolicy:
    connectionPool:
      tcp:
        maxConnections: 2
      http:
        http1MaxPendingRequests: 2
    outlierDetection:
      consecutive5xxErrors: 3
      interval: 5s
      baseEjectionTime: 30s
      maxEjectionPercent: 100
    loadBalancer:
      localityLbSetting:
        enabled: true
EOF

# Give istiod time to push this configuration to every proxy before the grader
# reads it back. By hand you spend longer than this reading the apply output;
# `astrona test` applies and grades in the same second, and would otherwise
# measure the previous state.
sleep 15
