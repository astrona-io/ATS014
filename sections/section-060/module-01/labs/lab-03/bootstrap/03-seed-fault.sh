#!/usr/bin/env bash
# The lab's starting state: ingress configuration broken in three places.
#   1. The Gateway serves starfleet.exmaple.com (a typo), not starfleet.example.com.
#   2. The VirtualService has no gateways: field, so its routes go to mesh
#      (the sidecars) and never reach the ingress gateway.
#   3. The VirtualService sends /productpage to host bridges, a Service that
#      does not exist.
# The Gateway's selector and port, and the Starfleet itself, are correct.
set -euo pipefail
cd "$(dirname "$0")"

kubectl apply -f ../resources/gateway-starfleet-gateway.yaml

kubectl apply -f ../resources/virtualservice-bridge.yaml

kubectl get gateway,virtualservice -n starfleet
