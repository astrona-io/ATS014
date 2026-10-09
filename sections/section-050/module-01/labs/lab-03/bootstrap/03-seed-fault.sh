#!/usr/bin/env bash
# The lab's starting state: somebody ran an abort drill on navcom and never
# scoped or removed it. Every signal to navcom fails with 500, and because the
# scout flight plan sends everyone to scout v2 (which calls navcom), every
# scout answer reports "Ratings service is currently unavailable".
# Scoping the drill to end-user: tester is the task.
set -euo pipefail

kubectl apply -f - <<'YAML'
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: scout
  namespace: starfleet
spec:
  host: scout
  subsets:
  - name: v1
    labels:
      version: v1
  - name: v2
    labels:
      version: v2
  - name: v3
    labels:
      version: v3
---
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: navcom
  namespace: starfleet
spec:
  host: navcom
  subsets:
  - name: v1
    labels:
      version: v1
---
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: scout
  namespace: starfleet
spec:
  hosts:
  - scout
  http:
  - route:
    - destination:
        host: scout
        subset: v2
---
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: navcom
  namespace: starfleet
spec:
  hosts:
  - navcom
  http:
  - fault:
      abort:
        httpStatus: 500
        percentage:
          value: 100
    route:
    - destination:
        host: navcom
        subset: v1
YAML
