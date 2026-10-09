#!/usr/bin/env bash
# The starting state for lab ats-014-lab-040-04-03:
#   - a probe DestinationRule with outlierDetection and localityLbSetting, so
#     the shuttle keeps every signal in its own orbit, local/zone-a
# Result: probe-zone-b receives no signals at all, so nobody knows whether the
# path to zone-b still works. The student replaces the preference with a fixed
# 80/20 split.
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
    outlierDetection:
      consecutive5xxErrors: 2
      interval: 5s
      baseEjectionTime: 30s
      maxEjectionPercent: 100
    loadBalancer:
      localityLbSetting:
        enabled: true
YAML
kubectl get destinationrule -n starfleet
