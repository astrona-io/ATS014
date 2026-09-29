#!/usr/bin/env bash
# Reference solution for lab 010-02, applied by `astrona test` in CI.
#
# Rule order is load-bearing: the redirect and the rewrite both match on a URI
# prefix, and the catch-all must sit last or it swallows them. The headers and
# corsPolicy blocks are per-rule, so every rule that serves traffic carries
# them - a rule that only redirects does not need them, because nothing is
# forwarded and the proxy writes the 301 itself.
set -euo pipefail

NS="routing-demo"

kubectl apply -f - <<'YAML'
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: notification-service
  namespace: routing-demo
spec:
  host: notification-service
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
  name: notification-service
  namespace: routing-demo
spec:
  hosts:
    - notification-service
  http:
    # 1. /legacy is answered by the proxy itself - no route, no pod involved.
    - match:
        - uri:
            prefix: /legacy
      redirect:
        uri: /notify
        redirectCode: 301

    # 2. /beta is rewritten onto the application's real path and pinned to v2.
    - match:
        - uri:
            prefix: /beta
      rewrite:
        uri: /
      headers:
        request:
          remove:
            - x-internal-token
        response:
          set:
            x-served-by: notification
      corsPolicy:
        allowOrigins:
          - exact: https://shop.example.com
        allowMethods:
          - GET
          - POST
      route:
        - destination:
            host: notification-service
            subset: v2

    # 3. everything else: v1, with the same header and CORS treatment.
    - headers:
        request:
          remove:
            - x-internal-token
        response:
          set:
            x-served-by: notification
      corsPolicy:
        allowOrigins:
          - exact: https://shop.example.com
        allowMethods:
          - GET
          - POST
      route:
        - destination:
            host: notification-service
            subset: v1
YAML

kubectl -n "$NS" rollout status deployment/tester --timeout=120s
# Give the push time to reach the tester's sidecar before the grader looks.
sleep 5
