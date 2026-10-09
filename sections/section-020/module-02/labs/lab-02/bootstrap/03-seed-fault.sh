#!/usr/bin/env bash
# The lab's starting state: a quiet shadow.
# The flight plan sends every signal to v1 and mirrors every signal to subset v2.
# The docking instructions define v2 with the label version=canary, which no
# probe ship carries. So the mirror cluster is empty: the proxy holds a mirror
# policy, the sender is perfectly happy, and the shadow receives nothing.
# Fixing the DestinationRule is the task - the VirtualService is correct.
set -euo pipefail

kubectl apply -f - <<'YAML'
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: probe
  namespace: starfleet
spec:
  host: probe
  subsets:
  - name: v1
    labels:
      version: v1
  - name: v2
    labels:
      version: canary
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
        subset: v1
    mirror:
      host: probe
      subset: v2
    mirrorPercentage:
      value: 100.0
YAML
