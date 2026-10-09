#!/usr/bin/env bash
# Reference solution: give the shuttle's own Sidecar the full list it needs.
# A selector Sidecar replaces the planet default, so it must list everything
# again: its own planet, istio-system and outpost.
set -euo pipefail

kubectl apply -f - <<'YAML'
apiVersion: networking.istio.io/v1
kind: Sidecar
metadata:
  name: shuttle-only
  namespace: starfleet
spec:
  workloadSelector:
    labels:
      app: shuttle
  outboundTrafficPolicy:
    mode: REGISTRY_ONLY
  egress:
  - hosts:
    - "./*"
    - "istio-system/*"
    - "outpost/*"
YAML
