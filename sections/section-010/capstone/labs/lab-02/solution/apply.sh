#!/usr/bin/env bash
# Reference solution, applied only by `astrona test` (the `testing:` block).
# `astrona run` never runs this, so students still do the work themselves.
# Kept in step with solution.md - if one changes, change the other.
set -euo pipefail

kubectl apply -f - <<'YAML'
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: probe
  namespace: starfleet
spec:
  host: probe
  exportTo:
  - "."
  - dock
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
  name: probe-hostname
  namespace: starfleet
spec:
  http:
  - match:
    - headers:
        x-canary:
          exact: "true"
    route:
    - destination:
        host: probe
        subset: v2
        port:
          number: 8000
  - route:
    - destination:
        host: probe
        subset: v1
        port:
          number: 8000
---
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: probe-delay
  namespace: starfleet
spec:
  http:
  - match:
    - headers:
        x-canary:
          exact: "true"
    timeout: 6s
    route:
    - destination:
        host: probe
        subset: v2
        port:
          number: 8000
  - timeout: 2s
    route:
    - destination:
        host: probe
        subset: v1
        port:
          number: 8000
---
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: probe
  namespace: starfleet
spec:
  hosts:
  - probe
  exportTo:
  - "."
  - dock
  http:
  - match:
    - uri:
        prefix: /hostname
    delegate:
      name: probe-hostname
      namespace: starfleet
  - match:
    - uri:
        prefix: /delay
    delegate:
      name: probe-delay
      namespace: starfleet
  - route:
    - destination:
        host: probe
        subset: v1
        port:
          number: 8000
YAML

# Give istiod a moment to push the configuration to the proxies.
sleep 10
