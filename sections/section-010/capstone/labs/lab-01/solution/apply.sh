#!/usr/bin/env bash
# Reference solution, applied only by `astrona test` (the `testing:` block).
# `astrona run` never runs this, so students still do the work themselves.
# Kept in step with solution.md - if one changes, change the other.
set -euo pipefail

kubectl apply -f - <<'EOF'
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: catalog
  namespace: storefront
spec:
  host: catalog
  subsets:
    - name: v1
      labels:
        version: v1
    - name: v2
      labels:
        version: v2
EOF

kubectl apply -f - <<'EOF'
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: catalog
  namespace: storefront
spec:
  hosts:
    - catalog
  http:
    - match:
        - headers:
            x-channel:
              exact: "mobile"
      route:
        - destination: { host: catalog, subset: v2 }
    - match:
        - uri:
            prefix: /notify/preview
      route:
        - destination: { host: catalog, subset: v2 }
    - match:
        - queryParams:
            beta:
              exact: "1"
      route:
        - destination: { host: catalog, subset: v2 }
    - route:
        - destination: { host: catalog, subset: v1 }
EOF

kubectl apply -f - <<'EOF'
apiVersion: networking.istio.io/v1
kind: Sidecar
metadata:
  name: default
  namespace: storefront
spec:
  egress:
    - hosts:
        - "./*"
        - "istio-system/*"
        - "partners/*"
EOF
sleep 3

# Give istiod time to push this configuration to every proxy before the grader
# reads it back. By hand you spend longer than this reading the apply output;
# `astrona test` applies and grades in the same second, and would otherwise
# measure the previous state.
sleep 15
