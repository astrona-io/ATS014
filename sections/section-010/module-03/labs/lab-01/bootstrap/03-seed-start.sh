#!/usr/bin/env bash
# The lab's starting state: a DestinationRule with subsets for all three scout
# versions, a VirtualService that sends every request to v1, and the patrol
# client pod that keeps sending requests for the whole lab.
# The rules are applied in the safe order (subsets first, then the route), and
# the patrol starts only after both have reached the proxies, so its access log
# starts clean.
set -euo pipefail
cd "$(dirname "$0")"

kubectl apply -f ../resources/destinationrule-scout.yaml
sleep 10

kubectl apply -f ../resources/virtualservice-scout.yaml
sleep 10

echo "==> The patrol"
kubectl apply -f manifests/patrol.yaml
kubectl wait -n starfleet --for=condition=Available deploy/patrol --timeout=300s
echo "==> Lab ats-014-lab-010-03-01 ready"
