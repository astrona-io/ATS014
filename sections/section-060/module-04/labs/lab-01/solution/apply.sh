#!/usr/bin/env bash
# Reference solution, applied only by `astrona test` (the `testing:` block).
# `astrona run` never runs this, so students still do the work themselves.
# Kept in step with solution.md - if one changes, change the other.
set -euo pipefail

kubectl -n istio-system create secret tls probe-tls \
  --key=/tmp/probe-example.key --cert=/tmp/probe-example.crt

kubectl apply -f - <<'YAML'
apiVersion: networking.istio.io/v1
kind: Gateway
metadata:
  name: probe-gateway
  namespace: starfleet
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 443
      name: https
      protocol: HTTPS
    hosts:
    - probe.example.com
    tls:
      mode: SIMPLE
      credentialName: probe-tls
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - probe.example.com
    tls:
      httpsRedirect: true
YAML

kubectl apply -f - <<'YAML'
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: probe
  namespace: starfleet
spec:
  hosts:
  - probe.example.com
  gateways:
  - probe-gateway
  http:
  - route:
    - destination:
        host: probe
        port:
          number: 8000
YAML

# Give istiod time to push this configuration and the secret to the gateway
# before the grader reads it back. `astrona test` applies and grades in the
# same second, and would otherwise measure the previous state.
sleep 15
