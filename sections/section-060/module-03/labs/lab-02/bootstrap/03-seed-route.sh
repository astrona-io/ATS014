#!/usr/bin/env bash
# The lab's starting state: an HTTPRoute with no Gateway to attach to.
# The HTTPRoute `bridge` names the Gateway `starfleet-gateway` in parentRefs,
# but no such Gateway exists, so the route has no status and no gateway proxy runs.
# Building the Gateway is the task - the HTTPRoute is correct.
set -euo pipefail

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
    - name: bridge
      port: 9080
YAML
echo "==> Lab ats-014-lab-060-03-02 ready"
