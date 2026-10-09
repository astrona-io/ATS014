#!/usr/bin/env bash
# The lab's starting state: a retry policy that re-sends every 5xx, three
# times. It also re-sends the probe's own 500 errors, which are app bugs that
# fail the same way every time, so the probe gets four requests for every one.
# Narrowing the policy is the task.
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
      attempts: 3
      retryOn: 5xx
    timeout: 10s
YAML
