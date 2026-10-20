#!/usr/bin/env bash
# The lab's starting state: a DestinationRule with one wrong label.
# The v2 subset selects version=v20, which no scout pod carries, so jason's
# requests (sent to v2 by the VirtualService) end in 503 UH.
# Fixing the DestinationRule is the task - the VirtualService is correct.
set -euo pipefail
cd "$(dirname "$0")"

kubectl apply -f ../resources/destinationrule-scout.yaml

kubectl apply -f ../resources/virtualservice-scout.yaml
echo "==> Lab ats-014-lab-010-01-03 ready"
