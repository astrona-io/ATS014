#!/usr/bin/env bash
# Reference solution, applied only by `astrona test` (the `testing:` block).
# `astrona run` never runs this, so students still do the work themselves.
# Kept in step with solution.md - if one changes, change the other.
set -euo pipefail

kubectl apply -f - <<'YAML'
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: vault
  namespace: starfleet
spec:
  hosts:
  - vault.outpost.example
  http:
  - match:
    - port: 8080
    route:
    - destination:
        host: vault.outpost.example
        port:
          number: 8443
YAML

kubectl apply -f - <<'YAML'
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: vault
  namespace: starfleet
spec:
  host: vault.outpost.example
  trafficPolicy:
    portLevelSettings:
    - port:
        number: 8443
      tls:
        mode: SIMPLE
        sni: vault.outpost.example
        insecureSkipVerify: true
YAML
