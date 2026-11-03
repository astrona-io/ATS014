#!/usr/bin/env bash
# The lab's starting state: an 80/20 tcp route that never splits anything.
# Two faults are in place on purpose:
#   1. The Service probe-tcp names its port "http", so Istio treats it as HTTP
#      and ignores the tcp route.
#   2. The DestinationRule defines subset v2 with the label version=canary,
#      which no probe pod carries. Once the port is fixed, connections picked
#      for v2 would have no endpoint.
# The VirtualService is correct and stays as it is.
set -euo pipefail
cd "$(dirname "$0")"

kubectl apply -f ../resources/service-probe-tcp.yaml
kubectl apply -f ../resources/destinationrule-probe-tcp.yaml
kubectl apply -f ../resources/virtualservice-probe-tcp.yaml
