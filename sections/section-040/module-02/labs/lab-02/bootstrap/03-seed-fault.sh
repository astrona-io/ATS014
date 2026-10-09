#!/usr/bin/env bash
# The lab's starting state: the shields on the probe are fine, but the flight
# plan's retry policy retries every 5xx up to 5 times. A probe that answers 503
# then receives each failing signal 6 times. Calming that storm is the task.
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
echo "==> Starting state applied: the probe's flight plan retries every 5xx five times"
