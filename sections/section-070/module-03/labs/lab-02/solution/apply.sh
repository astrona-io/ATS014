#!/usr/bin/env bash
# Reference solution, applied only by `astrona test` (the `testing:` block).
# `astrona run` never runs this, so students still do the work themselves.
# Kept in step with solution.md - if one changes, change the other.
set -euo pipefail

kubectl patch workloadentry freighter-vm-2 -n starfleet --type merge \
  -p '{"spec":{"labels":{"app":"freighter"}}}'

kubectl apply -f - <<'YAML'
apiVersion: networking.istio.io/v1
kind: ServiceEntry
metadata:
  name: freighter
  namespace: starfleet
spec:
  hosts:
  - freighter.starfleet.mesh
  location: MESH_INTERNAL
  resolution: STATIC
  ports:
  - number: 8080
    name: http
    protocol: HTTP
  workloadSelector:
    labels:
      app: freighter
YAML

# Give istiod time to push the change to the shuttle's proxy before grading.
sleep 15
