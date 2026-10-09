#!/usr/bin/env bash
# Reference solution: keep the delay drill on navcom (without the useless
# timeout), and put the 1-second abort window on jason's rule in the scout
# flight plan, the route the shuttle uses.
set -euo pipefail

kubectl apply -f - <<'YAML'
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
      delay:
        percentage:
          value: 100
        fixedDelay: 3s
    route:
    - destination:
        host: navcom
        subset: v1
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
  - match:
    - headers:
        end-user:
          exact: jason
    route:
    - destination:
        host: scout
        subset: v2
    timeout: 1s
  - route:
    - destination:
        host: scout
        subset: v1
YAML
