#!/usr/bin/env bash
# Reference solution, applied only by `astrona test` (the `testing:` block).
# `astrona run` never runs this, so students still do the work themselves.
# Kept in step with solution.md - if one changes, change the other.
set -euo pipefail

# Fault 1: the secret must be in istio-system, the namespace of the gateway pod.
kubectl -n istio-system create secret tls starfleet-tls \
  --key=/tmp/starfleet-example.key --cert=/tmp/starfleet-example.crt
kubectl -n starfleet delete secret starfleet-tls

# Fault 2: a PASSTHROUGH server needs a tls: match on the SNI, not an http: rule.
kubectl apply -f - <<'YAML'
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: archive
  namespace: starfleet
spec:
  hosts:
  - archive.starfleet.example.com
  gateways:
  - starfleet-gateway
  tls:
  - match:
    - port: 443
      sniHosts:
      - archive.starfleet.example.com
    route:
    - destination:
        host: archive
        port:
          number: 443
YAML

# Give istiod time to push this configuration and the secret to the gateway
# before the grader reads it back.
sleep 15
