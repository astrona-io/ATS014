#!/usr/bin/env bash
# The lab's starting state:
#   - a PeerAuthentication that sets mode STRICT on the probe pods
#   - a VirtualService that sends requests with the header "x-canary: true" to
#     subset v2 and all other requests to subset v1
#   - a DestinationRule with two mistakes:
#       1. the top-level tls mode is DISABLE, so the shuttle's proxy sends plain
#          text to pods that accept only mTLS
#       2. subset v2 sets its own loadBalancer (ROUND_ROBIN), which replaces the
#          host's consistentHash for v2, so v2 loses its session affinity
# Fixing both is the task.
# astrona runs this script with KUBECONFIG pointed at the lab cluster.
set -euo pipefail
cd "$(dirname "$0")"

kubectl apply -f manifests/peerauthentication-probe.yaml
kubectl apply -f manifests/virtualservice-probe.yaml
kubectl apply -f ../resources/probe-destinationrule.yaml
echo "==> Lab ats-014-lab-030-02-02 ready"
