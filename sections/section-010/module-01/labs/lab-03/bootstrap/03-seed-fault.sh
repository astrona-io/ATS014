#!/usr/bin/env bash
# The lab's starting state: docking instructions with one wrong label.
# The v2 subset selects version=v20, which no scout ship carries, so jason's
# signals (sent to v2 by the flight plan) end in 503 UH.
# Fixing the DestinationRule is the task - the VirtualService is correct.
set -euo pipefail

kubectl apply -f - <<'YAML'
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: scout
  namespace: starfleet
spec:
  host: scout
  subsets:
  - name: v1
    labels:
      version: v1
  - name: v2
    labels:
      version: v20
  - name: v3
    labels:
      version: v3
YAML

kubectl apply -f - <<'YAML'
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: scout
  namespace: starfleet
spec:
  hosts:
  - scout
  http:
  - match:
    - headers:
        end-user:
          exact: jason
    route:
    - destination:
        host: scout
        subset: v2
  - route:
    - destination:
        host: scout
        subset: v1
YAML
echo "==> Lab ats-014-lab-010-01-03 ready"
