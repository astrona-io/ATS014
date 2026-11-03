#!/usr/bin/env bash
# The capstone's starting state:
#   - a PeerAuthentication that sets mode STRICT on the probe pods
#   - a VirtualService that sends requests with the header "x-canary: true" to
#     subset v2 and all other requests to subset v1
# No DestinationRule exists. Writing it is the task.
# astrona runs this script with KUBECONFIG pointed at the lab cluster.
set -euo pipefail
cd "$(dirname "$0")"

kubectl apply -f manifests/peerauthentication-probe.yaml
kubectl apply -f manifests/virtualservice-probe.yaml
echo "==> Capstone ats-014-capstone-030-02 ready"
