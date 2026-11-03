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
    outlierDetection:
      consecutive5xxErrors: 2
      interval: 5s
      baseEjectionTime: 30s
      maxEjectionPercent: 100
YAML

# Give istiod time to push the new endpoints and cluster to every proxy before
# the grader sends requests.
sleep 15
