#!/usr/bin/env bash
# The lab's starting state: docking instructions that hash the sender's IP
# address. Every signal from the shuttle comes from the same address, so it
# always lands on the same probe pod, and the other three get nothing.
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
