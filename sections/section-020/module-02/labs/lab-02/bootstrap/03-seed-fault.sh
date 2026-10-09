#!/usr/bin/env bash
# The lab's starting state: the mirror target receives no copies.
# The VirtualService sends every request to v1 and mirrors every request to
# subset v2. The DestinationRule defines v2 with the label version=canary,
# which no probe pod carries. So the mirror cluster has no endpoints: the proxy
# holds a mirror policy, the client still gets 200 responses, and probe-v2
# receives nothing.
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
