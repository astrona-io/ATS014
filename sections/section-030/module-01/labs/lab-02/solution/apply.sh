#!/usr/bin/env bash
# Reference solution for lab 030-02, applied by `astrona test` in CI.
#
# The policy hangs off portLevelSettings rather than the host-level
# loadBalancer, and the cookie carries a ttl - which is what makes Istio ISSUE
# the cookie rather than only hashing one the client already had.
set -euo pipefail

kubectl apply -f - <<'YAML'
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: httpbin
  namespace: lb-demo
spec:
  host: httpbin
  trafficPolicy:
    portLevelSettings:
      - port:
          number: 8000
        loadBalancer:
          consistentHash:
            httpCookie:
              name: session-id
              ttl: 60s
YAML

kubectl -n lb-demo rollout status deployment/tester --timeout=120s
sleep 5
