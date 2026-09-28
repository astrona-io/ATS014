#!/usr/bin/env bash
# resilience-demo: an httpbin whose /delay/<s> and /status/<code> endpoints make
# slowness and failure controllable, plus a tester client.
# No VirtualService - that is the task.
set -euo pipefail

kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: resilience-demo
  labels:
    istio-injection: enabled
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: httpbin
  namespace: resilience-demo
  labels:
    app: httpbin
spec:
  replicas: 1
  selector:
    matchLabels:
      app: httpbin
  template:
    metadata:
      labels:
        app: httpbin
    spec:
      containers:
        - name: httpbin
          image: mccutchen/go-httpbin:v2.15.0
          command: ["/bin/go-httpbin", "-port", "8080"]
          ports:
            - containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: httpbin
  namespace: resilience-demo
  labels:
    app: httpbin
spec:
  ports:
    - name: http
      port: 8000
      targetPort: 8080
  selector:
    app: httpbin
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: tester
  namespace: resilience-demo
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
EOF

for d in httpbin tester; do
  kubectl -n resilience-demo rollout status "deployment/$d" --timeout=300s
done

echo "[lab] resilience-demo ready:"
kubectl -n resilience-demo get pods
echo "[lab] No VirtualService exists - there is no route timeout at all."
