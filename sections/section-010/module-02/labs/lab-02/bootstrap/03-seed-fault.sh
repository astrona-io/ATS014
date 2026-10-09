#!/usr/bin/env bash
# The lab's starting state.
# - A correct planet default for starfleet: its own planet, istio-system and
#   outpost, and REGISTRY_ONLY (uncharted planets go to the black hole).
# - A selector Sidecar for the shuttle that lists only "./*". It replaces the
#   planet default for the shuttle and inherits nothing, so the shuttle loses
#   outpost and istio-system, and its call to the probe ends in the black hole.
# Fixing shuttle-only is the task - the planet default is correct.
set -euo pipefail

kubectl apply -f - <<'YAML'
apiVersion: networking.istio.io/v1
kind: Sidecar
metadata:
  name: default
  namespace: starfleet
spec:
  outboundTrafficPolicy:
    mode: REGISTRY_ONLY
  egress:
  - hosts:
    - "./*"
    - "istio-system/*"
    - "outpost/*"
YAML

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
YAML
