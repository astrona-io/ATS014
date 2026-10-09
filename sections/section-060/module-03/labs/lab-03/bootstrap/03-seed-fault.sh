#!/usr/bin/env bash
# The lab's starting state: a correct gate and two broken flight plans.
#   Gateway   starfleet-gateway: correct, one HTTP listener for starfleet.example.com
#   HTTPRoute bridge: backendRefs names `brigde`, a Service that does not exist
#             (ResolvedRefs=False BackendNotFound, signals get 500 NC)
#   HTTPRoute scout:  parentRefs names `starfleet-gate`, a Gateway that does not
#             exist (no status at all, signals get 404 NR)
# Fixing the two routes is the task - the Gateway is correct.
set -euo pipefail

kubectl apply -f - <<'YAML'
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: starfleet-gateway
  namespace: starfleet
  annotations:
    networking.istio.io/service-type: ClusterIP
spec:
  gatewayClassName: istio
  listeners:
  - name: http
    port: 80
    protocol: HTTP
    hostname: starfleet.example.com
    allowedRoutes:
      namespaces:
        from: Same
YAML

kubectl wait -n starfleet --for=condition=Programmed gateway/starfleet-gateway --timeout=180s
kubectl rollout status deploy/starfleet-gateway-istio -n starfleet --timeout=180s

kubectl apply -f - <<'YAML'
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: bridge
  namespace: starfleet
spec:
  parentRefs:
  - name: starfleet-gateway
  hostnames:
  - starfleet.example.com
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /productpage
    backendRefs:
    - name: brigde
      port: 9080
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: scout
  namespace: starfleet
spec:
  parentRefs:
  - name: starfleet-gate
  hostnames:
  - starfleet.example.com
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /reviews
    backendRefs:
    - name: scout
      port: 9080
YAML
echo "==> Lab ats-014-lab-060-03-03 ready"
