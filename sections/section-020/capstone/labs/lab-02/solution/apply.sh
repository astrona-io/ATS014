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
  name: probe
  namespace: starfleet
spec:
  hosts:
  - probe
  http:
  - match:
    - headers:
        x-tester:
          exact: "yes"
    route:
    - destination:
        host: probe
        subset: v2
  - route:
    - destination:
        host: probe
        subset: v1
      weight: 80
    - destination:
        host: probe
        subset: v2
      weight: 20
    mirror:
      host: probe-shadow
    mirrorPercentage:
      value: 100.0
---
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: probe-tcp
  namespace: starfleet
spec:
  host: probe-tcp
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
  name: probe-tcp
  namespace: starfleet
spec:
  hosts:
  - probe-tcp
  tcp:
  - match:
    - port: 8000
    route:
    - destination:
        host: probe-tcp
        subset: v1
        port:
          number: 8000
      weight: 70
    - destination:
        host: probe-tcp
        subset: v2
        port:
          number: 8000
      weight: 30
YAML
