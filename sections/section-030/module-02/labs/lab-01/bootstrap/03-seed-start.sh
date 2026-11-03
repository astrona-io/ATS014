#!/usr/bin/env bash
# The lab's starting state:
#   - a PeerAuthentication that sets mode STRICT on the probe pods
#   - a VirtualService that sends requests with the header "x-canary: true" to
#     subset v2 and all other requests to subset v1
# No DestinationRule exists, so the subsets v1 and v2 are not defined yet and
# the VirtualService has nothing to route to. Writing the DestinationRule is the task.
# astrona runs this script with KUBECONFIG pointed at the lab cluster.
set -euo pipefail
cd "$(dirname "$0")"

kubectl apply -f manifests/peerauthentication-probe.yaml
kubectl apply -f manifests/virtualservice-probe.yaml
echo "==> Lab ats-014-lab-030-02-01 ready"
