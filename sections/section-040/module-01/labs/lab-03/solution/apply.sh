#!/usr/bin/env bash
# Reference solution: retry only 503, at most 2 times, 1 second per try, and a
# route timeout that leaves room for all three tries.
set -euo pipefail

kubectl apply -f - <<'YAML'
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: probe
  namespace: starfleet
spec:
  hosts:
  - probe
  http:
  - route:
    - destination:
        host: probe
    retries:
      attempts: 2
      perTryTimeout: 1s
      retryOn: "503"
    timeout: 4s
YAML
