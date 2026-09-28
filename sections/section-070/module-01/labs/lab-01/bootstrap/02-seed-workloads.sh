#!/usr/bin/env bash
# egress-demo  : an injected client
# outside-mesh : two bare pods with NO Service, so they are not in the mesh
#                registry at all - they stand in for external endpoints and
#                need no internet access.
# Their addresses are written to /tmp/ for the student and the grader.
set -euo pipefail

kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: egress-demo
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
  namespace: egress-demo
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
    spec:
      containers:
        - name: tester
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
---
apiVersion: v1
kind: Pod
metadata:
  name: forbidden-api
  namespace: outside-mesh
  labels:
    app: forbidden-api
spec:
  containers:
    - name: app
      image: mccutchen/go-httpbin:v2.15.0
      command: ["/bin/go-httpbin", "-port", "8080"]
      ports:
        - containerPort: 8080
EOF

kubectl -n egress-demo rollout status deployment/tester --timeout=300s
kubectl -n outside-mesh wait --for=condition=Ready pod/partner-api   --timeout=300s
kubectl -n outside-mesh wait --for=condition=Ready pod/forbidden-api --timeout=300s

PARTNER_IP=$(kubectl -n outside-mesh get pod partner-api   -o jsonpath='{.status.podIP}')
FORBIDDEN_IP=$(kubectl -n outside-mesh get pod forbidden-api -o jsonpath='{.status.podIP}')

printf '%s' "$PARTNER_IP"   > /tmp/partner-ip
printf '%s' "$FORBIDDEN_IP" > /tmp/forbidden-ip

echo
echo "[lab] Two endpoints exist OUTSIDE the mesh registry (bare pods, no Service):"
echo "[lab]   partner-api   ${PARTNER_IP}:8080   <- you will register this one"
echo "[lab]   forbidden-api ${FORBIDDEN_IP}:8080 <- this one must stay blocked"
echo "[lab] The addresses are also in /tmp/partner-ip and /tmp/forbidden-ip"
echo "[lab] The mesh is REGISTRY_ONLY, so both are currently refused with 502."
echo "[lab] No ServiceEntry exists - that is the task."
