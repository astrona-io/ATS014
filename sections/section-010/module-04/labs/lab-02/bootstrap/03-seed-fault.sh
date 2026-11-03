#!/usr/bin/env bash
# The lab's starting state: a DestinationRule and a VirtualService for the probe
# in starfleet, both with exportTo ["."]. Only proxies in starfleet receive them,
# so clients in dock and depot are not routed to v2.
# Fixing the exportTo fields is the task.
set -euo pipefail
cd "$(dirname "$0")"

kubectl apply -f ../resources/destinationrule-probe.yaml
kubectl apply -f ../resources/virtualservice-probe.yaml

# Give istiod a moment to push the configuration to the proxies.
sleep 10
kubectl get destinationrule,virtualservice -n starfleet
