#!/usr/bin/env bash
# Reference solution: keep the abort drill on navcom, but only for signals
# with end-user: tester, and add a plain rule below it for everyone else.
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
  - match:
    - headers:
        end-user:
          exact: tester
    fault:
      abort:
        httpStatus: 500
        percentage:
          value: 100
    route:
    - destination:
        host: navcom
        subset: v1
  - route:
    - destination:
        host: navcom
        subset: v1
YAML
