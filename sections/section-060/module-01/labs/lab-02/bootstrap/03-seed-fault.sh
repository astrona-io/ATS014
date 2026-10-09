#!/usr/bin/env bash
# The lab's starting state: an ingress gateway with no listener.
# The Gateway selects istio=ingressgateway (the label of an istioctl install),
# but this Helm install labels its gateway pods istio=ingress. No pod gets the
# listener, so every request to the ingress gateway gets no reply (curl prints 000).
# Fixing the Gateway is the task - the VirtualService is correct.
set -euo pipefail

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
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - starfleet.example.com
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
  gateways:
  - starfleet-gateway
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
        host: bridge
        port:
          number: 9080
YAML

kubectl get gateway,virtualservice -n starfleet
