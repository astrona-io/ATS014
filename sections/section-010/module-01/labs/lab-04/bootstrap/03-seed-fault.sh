#!/usr/bin/env bash
# The lab's starting state: a correct DestinationRule in starfleet, and a
# VirtualService with three faults in it:
#   1. it lives in the wrong namespace (default) with the short host
#      `scout`, so it describes scout.default.svc.cluster.local, a Service that
#      does not exist - none of its rules ever fire for the shuttle
#   2. its catch-all route comes first, so the jason rule below it is dead
#   3. the jason rule names subset v4, which the DestinationRule never defines
# Repairing the VirtualService is the task - the DestinationRule is correct.
set -euo pipefail
cd "$(dirname "$0")"

kubectl apply -f ../resources/destinationrule-scout.yaml

kubectl apply -f ../resources/virtualservice-scout.yaml
echo "==> Lab ats-014-lab-010-01-04 ready"
