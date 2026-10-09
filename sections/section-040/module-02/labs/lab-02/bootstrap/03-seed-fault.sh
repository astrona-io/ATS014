#!/usr/bin/env bash
# The lab's starting state: the connection pool on the probe is fine, but the
# VirtualService's retry policy retries every 5xx up to 5 times. A probe that
# answers 503 then receives each failing request 6 times. Stopping that retry
# storm is the task.
set -euo pipefail

kubectl apply -f - <<'YAML'
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: probe
  namespace: starfleet
spec:
  host: probe
  trafficPolicy:
    connectionPool:
      tcp:
        maxConnections: 1
      http:
        http1MaxPendingRequests: 1
        maxRequestsPerConnection: 1
YAML

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
      attempts: 5
      perTryTimeout: 1s
      retryOn: 5xx
    timeout: 10s
YAML
echo "==> Starting state applied: the probe's VirtualService retries every 5xx five times"
