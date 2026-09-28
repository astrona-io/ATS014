#!/usr/bin/env bash
# Reference solution, applied only by `astrona test` (the `testing:` block).
# `astrona run` never runs this, so students still do the work themselves.
# Kept in step with solution.md - if one changes, change the other.
set -euo pipefail

kubectl apply -f - <<'EOF'
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: httpbin
  namespace: lb-demo
spec:
  host: httpbin
  trafficPolicy:
    loadBalancer:
      consistentHash:
        httpHeaderName: x-user
  subsets:
    - name: stable
      labels:
        version: stable
    - name: canary
      labels:
        version: canary
      trafficPolicy:
        loadBalancer:
          simple: ROUND_ROBIN
EOF

kubectl apply -f - <<'EOF'
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: httpbin
  namespace: lb-demo
spec:
  hosts:
    - httpbin
  http:
    - match:
        - headers:
            x-track:
              exact: "canary"
      route:
        - destination:
            host: httpbin
            subset: canary
    - route:
        - destination:
            host: httpbin
            subset: stable
EOF

# Give istiod time to push this configuration to every proxy before the grader
# reads it back. By hand you spend longer than this reading the apply output;
# `astrona test` applies and grades in the same second, and would otherwise
# measure the previous state.
sleep 15
