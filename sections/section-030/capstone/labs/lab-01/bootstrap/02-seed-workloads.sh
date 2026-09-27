#!/usr/bin/env bash
# sessions: httpbin in two versions behind one Service.
#   stable - 3 replicas, holds per-user state in memory (notionally)
#   canary - 2 replicas, the shadow target
# Plus a tester client. No DestinationRule or VirtualService - that is the task.
set -euo pipefail

kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: sessions
  labels:
    istio-injection: enabled
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: httpbin-stable
  namespace: sessions
  labels:
    app: httpbin
    version: stable
spec:
  replicas: 3
  selector:
    matchLabels:
      app: httpbin
      version: stable
  template:
    metadata:
      labels:
        app: httpbin
        version: stable
    spec:
      containers:
        - name: httpbin
          image: mccutchen/go-httpbin:v2.15.0
          args: ["-port", "8080"]
          ports:
            - containerPort: 8080
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: httpbin-canary
  namespace: sessions
  labels:
    app: httpbin
    version: canary
spec:
  replicas: 2
  selector:
    matchLabels:
      app: httpbin
      version: canary
  template:
    metadata:
      labels:
        app: httpbin
        version: canary
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
  namespace: sessions
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
  namespace: sessions
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

for d in httpbin-stable httpbin-canary tester; do
  kubectl -n sessions rollout status "deployment/$d" --timeout=300s
done

echo "[capstone] sessions ready:"
kubectl -n sessions get pods -o wide
echo "[capstone] No DestinationRule and no VirtualService exist - that is the task."
