#!/usr/bin/env bash
# The lab's starting state: a correct DestinationRule (subsets v1, v2, v3)
# and a VirtualService that sends every scout request to v1.
# Turning that VirtualService into a three-way weighted split is the task.
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
