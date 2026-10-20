#!/usr/bin/env bash
# The starting state for lab ats-014-lab-040-04-03:
#   - a probe DestinationRule with outlierDetection and localityLbSetting, so
#     the shuttle keeps every request in its own zone, local/zone-a
# Result: probe-zone-b receives no requests at all, so nobody knows whether the
# path to zone-b still works. The student replaces the preference with a fixed
# 80/20 split.
set -euo pipefail
cd "$(dirname "$0")"

kubectl apply -f ../resources/destinationrule-probe.yaml
kubectl get destinationrule -n starfleet
