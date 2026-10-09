#!/usr/bin/env bash
# The lab's starting state: an arrival gate broken in three places.
#   1. The Gateway serves starfleet.exmaple.com (a typo), not starfleet.example.com.
#   2. The VirtualService has no gateways: field, so its routes go to mesh
#      (the sidecars) and never reach the gate.
#   3. The VirtualService sends /productpage to host bridges, a ship that does
#      not exist.
# The gate's selector, port and the Starfleet itself are correct.
set -euo pipefail

kubectl apply -f - <<'YAML'
apiVersion: networking.istio.io/v1
kind: Gateway
metadata:
  name: starfleet-gateway
  namespace: starfleet
spec:
  selector:
    istio: ingress
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - starfleet.exmaple.com
YAML

kubectl apply -f - <<'YAML'
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: bridge
  namespace: starfleet
spec:
  hosts:
  - starfleet.example.com
  http:
  - match:
    - uri:
        exact: /productpage
    - uri:
        prefix: /static
    - uri:
        exact: /login
    - uri:
        exact: /logout
    - uri:
        prefix: /api/v1/products
    route:
    - destination:
        host: bridges
        port:
          number: 9080
YAML

kubectl get gateway,virtualservice -n starfleet
