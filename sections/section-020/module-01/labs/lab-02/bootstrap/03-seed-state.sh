#!/usr/bin/env bash
# The lab's starting state: a correct DestinationRule (subsets v1, v2, v3)
# and a VirtualService that sends every scout request to v1.
# Turning that VirtualService into a three-way weighted split is the task.
set -euo pipefail
cd "$(dirname "$0")"

kubectl apply -f ../resources/destinationrule-scout.yaml

kubectl apply -f ../resources/virtualservice-scout.yaml
echo "==> Lab ats-014-lab-020-01-02 ready"
