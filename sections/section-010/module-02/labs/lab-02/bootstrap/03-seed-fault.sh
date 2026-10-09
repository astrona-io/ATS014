#!/usr/bin/env bash
# The lab's starting state.
# - A correct namespace-wide default Sidecar for starfleet: its own namespace,
#   istio-system and outpost, and REGISTRY_ONLY (hosts not in the list go to
#   the BlackHoleCluster).
# - A selector Sidecar for the shuttle that lists only "./*". It replaces the
#   namespace default for the shuttle and inherits nothing, so the shuttle loses
#   outpost and istio-system, and its call to the probe ends in the BlackHoleCluster.
# Fixing shuttle-only is the task - the namespace default is correct.
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
