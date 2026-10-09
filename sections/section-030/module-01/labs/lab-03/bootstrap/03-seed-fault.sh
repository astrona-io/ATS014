#!/usr/bin/env bash
# The lab's starting state: a DestinationRule that hashes the client's IP
# address. Every request from the shuttle comes from the same address, so it
# always goes to the same probe pod, and the other three get nothing.
# Replacing this policy with an even spread is the task.
set -euo pipefail

kubectl apply -f - <<'YAML'
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: probe
  namespace: starfleet
spec:
  host: probe
  trafficPolicy:
    loadBalancer:
      consistentHash:
        useSourceIp: true
YAML
echo "==> Lab ats-014-lab-030-01-03 ready"
