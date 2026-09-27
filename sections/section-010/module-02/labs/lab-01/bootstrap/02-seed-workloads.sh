#!/usr/bin/env bash
# Three injected namespaces so scoping has something to include and something to
# exclude: a client in sidecar-demo, and a backend in each of sidecar-other and
# sidecar-third. No Sidecar resource is created - that is the task.
set -euo pipefail

kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: sidecar-demo
  labels:
    istio-injection: enabled
---
apiVersion: v1
kind: Namespace
metadata:
  name: sidecar-other
  labels:
    istio-injection: enabled
---
apiVersion: v1
kind: Namespace
metadata:
  name: sidecar-third
  labels:
    istio-injection: enabled
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: tester
  namespace: sidecar-demo
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
apiVersion: apps/v1
kind: Deployment
metadata:
  name: local-backend
  namespace: sidecar-demo
  labels:
    app: local-backend
spec:
  replicas: 1
  selector:
    matchLabels:
      app: local-backend
  template:
    metadata:
      labels:
        app: local-backend
    spec:
      containers:
        - name: httpbin
          image: mccutchen/go-httpbin:v2.15.0
          args: ["-port", "8080"]
          ports:
            - containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: local-backend
  namespace: sidecar-demo
spec:
  ports:
    - name: http
      port: 8000
      targetPort: 8080
  selector:
    app: local-backend
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: httpbin
  namespace: sidecar-other
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
          args: ["-port", "8080"]
          ports:
            - containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: httpbin
  namespace: sidecar-other
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
  name: httpbin
  namespace: sidecar-third
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
          args: ["-port", "8080"]
          ports:
            - containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: httpbin
  namespace: sidecar-third
spec:
  ports:
    - name: http
      port: 8000
      targetPort: 8080
  selector:
    app: httpbin
EOF

kubectl -n sidecar-demo rollout status deployment/tester --timeout=300s
kubectl -n sidecar-demo rollout status deployment/local-backend --timeout=300s
kubectl -n sidecar-other rollout status deployment/httpbin --timeout=300s
kubectl -n sidecar-third rollout status deployment/httpbin --timeout=300s

echo "[lab] Namespaces ready. The tester proxy currently knows about all of them:"
kubectl exec -n sidecar-demo deploy/tester -c istio-proxy -- true 2>/dev/null || true
echo "[lab] No Sidecar resource exists - that is the task."
