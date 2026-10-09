#!/usr/bin/env bash
# The starting state for lab ats-014-lab-040-04-02:
#   - probe-zone-b loses its istio-locality label, so it falls back to the
#     node's locality (local/zone-a), the same locality as probe-zone-a
#   - a correct DestinationRule for the probe with outlierDetection and
#     localityLbSetting, so the shuttle prefers its own zone
# Result: the shuttle sees two endpoints in its own zone and splits its requests
# between them, although probe-zone-b is meant to be in zone-b.
set -euo pipefail

kubectl -n starfleet patch deployment probe-zone-b --type json \
  -p '[{"op":"remove","path":"/spec/template/metadata/labels/istio-locality"}]'
kubectl -n starfleet rollout status deployment probe-zone-b --timeout=300s

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
sleep 5
kubectl get pods -n starfleet --show-labels
