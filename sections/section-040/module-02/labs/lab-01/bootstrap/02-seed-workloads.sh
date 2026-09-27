#!/usr/bin/env bash
# circuit-demo: a backend plus a fortio load generator, because this module is
# about concurrency and curl in a loop is sequential.
# No DestinationRule - that is the task.
set -euo pipefail

kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: circuit-demo
  labels:
    istio-injection: enabled
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: notification-service-v1
  namespace: circuit-demo
  labels:
    app: notification-service
    version: v1
spec:
  replicas: 1
  selector:
    matchLabels:
      app: notification-service
      version: v1
  template:
    metadata:
      labels:
        app: notification-service
        version: v1
    spec:
      containers:
        - name: notification-service
          image: kubeteam/notification-service:v1
          ports:
            - containerPort: 8084
          env:
            - name: SERVICE_PORT
              value: "8084"
---
apiVersion: v1
kind: Service
metadata:
  name: notification-service
  namespace: circuit-demo
  labels:
    app: notification-service
spec:
  ports:
    - name: http
      port: 80
      targetPort: 8084
  selector:
    app: notification-service
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fortio
  namespace: circuit-demo
  labels:
    app: fortio
spec:
  replicas: 1
  selector:
    matchLabels:
      app: fortio
  template:
    metadata:
      labels:
        app: fortio
    spec:
      containers:
        - name: fortio
          image: fortio/fortio:latest_release
          ports:
            - containerPort: 8080
EOF

kubectl -n circuit-demo rollout status deployment/notification-service-v1 --timeout=300s
kubectl -n circuit-demo rollout status deployment/fortio --timeout=300s

echo "[lab] circuit-demo ready:"
kubectl -n circuit-demo get pods
echo "[lab] No DestinationRule exists - concurrency is unbounded."
