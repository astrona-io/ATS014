#!/usr/bin/env bash
# fault-demo: a two-hop chain so a SERVICE experiences the injected failure,
# not just curl.
#   booking-service      calls notification-service on every /book
#   notification-service the dependency the faults are aimed at
# There is no permanent client pod - use `kubectl run --rm`.
# No VirtualService - that is the task.
set -euo pipefail

kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: fault-demo
  labels:
    istio-injection: enabled
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: booking-service-v1
  namespace: fault-demo
  labels:
    app: booking-service
    version: v1
spec:
  replicas: 1
  selector:
    matchLabels:
      app: booking-service
      version: v1
  template:
    metadata:
      labels:
        app: booking-service
        version: v1
    spec:
      containers:
        - name: booking-service
          image: kubeteam/booking-service:v1
          ports:
            - containerPort: 8083
          env:
            - name: SERVICE_PORT
              value: "8083"
            - name: NOTIFICATION_SERVICE_URL
              value: "notification-service"
            - name: NOTIFICATION_SERVICE_PORT
              value: "80"
---
apiVersion: v1
kind: Service
metadata:
  name: booking-service
  namespace: fault-demo
  labels:
    app: booking-service
spec:
  ports:
    - name: http
      port: 80
      targetPort: 8083
  selector:
    app: booking-service
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: notification-service-v1
  namespace: fault-demo
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
  namespace: fault-demo
  labels:
    app: notification-service
spec:
  ports:
    - name: http
      port: 80
      targetPort: 8084
  selector:
    app: notification-service
EOF

for d in booking-service-v1 notification-service-v1; do
  kubectl -n fault-demo rollout status "deployment/$d" --timeout=300s
done

echo "[lab] fault-demo ready:"
kubectl -n fault-demo get pods
echo "[lab] No VirtualService exists - that is the task."
