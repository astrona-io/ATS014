#!/usr/bin/env bash
# Reference solution, applied only by `astrona test` (the `testing:` block).
# `astrona run` never runs this, so students still do the work themselves.
# Kept in step with solution.md - if one changes, change the other.
set -euo pipefail

kubectl -n istio-system create secret tls starfleet-tls \
  --key=/tmp/starfleet-edge.key --cert=/tmp/starfleet-edge.crt

kubectl apply -f - <<'YAML'
apiVersion: networking.istio.io/v1
kind: Gateway
metadata:
  name: starfleet-gateway
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
    - starfleet.example.com
    tls:
      mode: SIMPLE
      credentialName: starfleet-tls
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - starfleet.example.com
    tls:
      httpsRedirect: true
---
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: probe
  namespace: starfleet
spec:
  host: probe
  subsets:
  - name: v1
    labels:
      version: v1
  - name: v2
    labels:
      version: v2
---
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: starfleet
  namespace: starfleet
spec:
  hosts:
  - starfleet.example.com
  gateways:
  - starfleet-gateway
  http:
  - match:
    - uri:
        prefix: /productpage
    route:
    - destination:
        host: bridge
        port:
          number: 9080
  - match:
    - uri:
        prefix: /hostname
      headers:
        x-channel:
          exact: beta
    route:
    - destination:
        host: probe
        subset: v2
        port:
          number: 8000
  - match:
    - uri:
        prefix: /hostname
    route:
    - destination:
        host: probe
        subset: v1
        port:
          number: 8000
YAML

# Give istiod time to push this configuration and the secret to the gateway
# before the grader reads it back.
sleep 15
