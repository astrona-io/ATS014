#!/usr/bin/env bash
# egwgw-demo   : two injected clients with DIFFERENT labels, so sourceLabels
#                has something to distinguish
# outside-mesh : a bare pod (no Service) standing in for an external endpoint
set -euo pipefail

kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: egwgw-demo
  labels:
    istio-injection: enabled
---
apiVersion: v1
kind: Namespace
metadata:
  name: outside-mesh
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: tester
  namespace: egwgw-demo
  labels:
    app: tester
spec:
  replicas: 1
  selector:
    matchLabels:
      app: tester
  template:
    metadata:
      labels:
        app: tester
        egress-allowed: "true"
    spec:
      containers:
        - name: tester
          image: curlimages/curl
          command: ["sh", "-c", "while true; do sleep 30; done"]
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: other-client
  namespace: egwgw-demo
  labels:
    app: other-client
spec:
  replicas: 1
  selector:
    matchLabels:
      app: other-client
  template:
    metadata:
      labels:
        app: other-client
    spec:
      containers:
        - name: curl
          image: curlimages/curl
          command: ["sh", "-c", "while true; do sleep 30; done"]
---
apiVersion: v1
kind: Pod
metadata:
  name: partner-api
  namespace: outside-mesh
  labels:
    app: partner-api
spec:
  containers:
    - name: app
      image: mccutchen/go-httpbin:v2.15.0
      command: ["/bin/go-httpbin", "-port", "8080"]
      ports:
        - containerPort: 8080
EOF

kubectl -n egwgw-demo rollout status deployment/tester       --timeout=300s
kubectl -n egwgw-demo rollout status deployment/other-client --timeout=300s
kubectl -n outside-mesh wait --for=condition=Ready pod/partner-api --timeout=300s

PARTNER_IP=$(kubectl -n outside-mesh get pod partner-api -o jsonpath='{.status.podIP}')
printf '%s' "$PARTNER_IP" > /tmp/partner-ip

echo
echo "[lab] An endpoint exists OUTSIDE the mesh registry (bare pod, no Service):"
echo "[lab]   partner-api  ${PARTNER_IP}:8080   (also in /tmp/partner-ip)"
echo "[lab] Two injected clients, with different labels:"
echo "[lab]   tester        app=tester, egress-allowed=true"
echo "[lab]   other-client  app=other-client"
echo "[lab] The egress gateway is running and carrying nothing."
echo "[lab] No ServiceEntry, Gateway or VirtualService exists - that is the task."
