#!/usr/bin/env bash
# The lab's starting state: correct docking instructions (subsets v1, v2, v3)
# and a flight plan that sends every scout signal to v1.
# Turning that flight plan into a three-way weighted split is the task.
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
      version: v2
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
  - route:
    - destination:
        host: scout
        subset: v1
YAML
echo "==> Lab ats-014-lab-020-01-02 ready"
