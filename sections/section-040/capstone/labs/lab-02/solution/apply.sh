#!/usr/bin/env bash
# Reference solution, applied only by `astrona test` (the `testing:` block).
# `astrona run` never runs this, so students still do the work themselves.
# Kept in step with solution.md - if one changes, change the other.
set -euo pipefail

kubectl apply -f - <<'YAML'
apiVersion: v1
kind: Service
metadata:
  name: probe
  namespace: starfleet
  labels:
    app: probe
spec:
  selector:
    app: probe
  trafficDistribution: PreferClose
  ports:
  - name: http
    port: 8000
    targetPort: 8080
YAML

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
        connectTimeout: 2s
        maxConnectionDuration: 5m
        tcpKeepalive:
          time: 30s
          interval: 10s
          probes: 3
      http:
        idleTimeout: 60s
    outlierDetection:
      consecutive5xxErrors: 2
      interval: 5s
      baseEjectionTime: 30s
      maxEjectionPercent: 100
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
    timeout: 3s
    retries:
      attempts: 2
      perTryTimeout: 1s
      retryOn: 5xx
YAML

# Give istiod time to push the new configuration to every proxy before the
# grader sends requests.
sleep 15
