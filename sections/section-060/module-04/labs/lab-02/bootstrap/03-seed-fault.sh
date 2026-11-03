#!/usr/bin/env bash
# The lab's starting state. Two faults:
#   1. The secret starfleet-tls, which the Gateway names in credentialName, is
#      in the namespace starfleet. The gateway pod reads secrets only from
#      istio-system, so the HTTPS server for starfleet.example.com has no
#      certificate.
#   2. The VirtualService archive routes with an http: rule, but the Gateway
#      server for archive.starfleet.example.com is PASSTHROUGH. The gateway
#      never decrypts that traffic, so an http: rule cannot match it. A tls:
#      match on sniHosts is needed.
# The Gateway modes and the Service archive are correct. Fixing the secret and
# the route is the task.
set -euo pipefail
cd "$(dirname "$0")"

kubectl create secret tls starfleet-tls -n starfleet \
  --key=/tmp/starfleet-example.key --cert=/tmp/starfleet-example.crt

kubectl apply -f ../resources/gateway-starfleet-gateway.yaml
kubectl apply -f ../resources/virtualservice-probe.yaml
kubectl apply -f ../resources/virtualservice-archive.yaml
