#!/usr/bin/env bash
# The lab's starting state: a correct Gateway and two broken HTTPRoutes.
#   Gateway   starfleet-gateway: correct, one HTTP listener for starfleet.example.com
#   HTTPRoute bridge: backendRefs names `brigde`, a Service that does not exist
#             (ResolvedRefs=False BackendNotFound, requests get 500 NC)
#   HTTPRoute scout:  parentRefs names `starfleet-gate`, a Gateway that does not
#             exist (no status at all, requests get 404 NR)
# Fixing the two routes is the task - the Gateway is correct.
set -euo pipefail
cd "$(dirname "$0")"

kubectl apply -f ../resources/gateway-starfleet-gateway.yaml

kubectl wait -n starfleet --for=condition=Programmed gateway/starfleet-gateway --timeout=180s
kubectl rollout status deploy/starfleet-gateway-istio -n starfleet --timeout=180s

kubectl apply -f ../resources/httproute-bridge-and-httproute-scout.yaml
echo "==> Lab ats-014-lab-060-03-03 ready"
