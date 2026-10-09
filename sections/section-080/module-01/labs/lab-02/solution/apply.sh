#!/usr/bin/env bash
# Reference solution, applied only by `astrona test` (the `testing:` block).
# `astrona run` never runs this, so students still do the work themselves.
# Kept in step with solution.md - if one changes, change the other.
set -euo pipefail

kubectl apply -f - <<'YAML'
apiVersion: networking.istio.io/v1
kind: Gateway
metadata:
  name: departure-gate
  namespace: starfleet
spec:
  selector:
    istio: egress
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - relay.outpost.example
---
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: relay-via-departure-gate
  namespace: starfleet
spec:
  hosts:
  - relay.outpost.example
  gateways:
  - mesh
  - departure-gate
  http:
  - match:
    - gateways:
      - mesh
      port: 8080
    route:
    - destination:
        host: istio-egress.istio-egress.svc.cluster.local
        subset: relay
        port:
          number: 80
  - match:
    - gateways:
      - departure-gate
      port: 80
    route:
    - destination:
        host: relay.outpost.example
        port:
          number: 8080
YAML

# Give istiod time to push the change to the shuttle and the gateway before the
# grader reads it back.
sleep 15
