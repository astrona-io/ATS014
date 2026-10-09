#!/usr/bin/env bash
# Reference solution, applied only by `astrona test` (the `testing:` block).
# `astrona run` never runs this, so students still do the work themselves.
# Kept in step with solution.md - if one changes, change the other.
# Moves the relay's ServiceEntry onto the starfleet planet (where the Sidecar's
# "./*" takes it in), declares its port HTTP, and keeps it private.
set -euo pipefail

RELAY_IP=$(kubectl -n outpost get pod relay -o jsonpath='{.status.podIP}')

kubectl delete serviceentry relay -n charts --ignore-not-found

kubectl apply -f - <<YAML
apiVersion: networking.istio.io/v1
kind: ServiceEntry
metadata:
  name: relay
  namespace: starfleet
spec:
  hosts:
  - relay.outpost.example
  exportTo:
  - "."
  addresses:
  - ${RELAY_IP}
  ports:
  - number: 8080
    name: http
    protocol: HTTP
  location: MESH_EXTERNAL
  resolution: STATIC
  endpoints:
  - address: ${RELAY_IP}
YAML

# Give istiod time to push the change before the grader reads it back.
sleep 15
