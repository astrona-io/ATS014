#!/usr/bin/env bash
# Reference solution, applied only by `astrona test` (the `testing:` block).
# `astrona run` never runs this, so students still do the work themselves.
# Kept in step with solution.md - if one changes, change the other.
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
        connectTimeout: 2s
        maxConnectionDuration: 10m
        tcpKeepalive:
          time: 60s
          interval: 10s
          probes: 4
      http:
        idleTimeout: 90s
YAML

# Give istiod time to push the new cluster to every proxy before the grader
# reads it back.
sleep 15
