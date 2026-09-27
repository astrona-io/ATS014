#!/usr/bin/env bash
# orders: a two-hop chain so a SERVICE experiences the injected failures.
#   booking-service      calls notification-service on every /book, forwarding headers
#   notification-service the dependency the faults are aimed at
# There is no permanent client pod - use `kubectl run --rm`.
# No VirtualService - that is the task.
set -euo pipefail

kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: orders
  labels:
    istio-injection: enabled
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: booking-service-v1
  namespace: orders
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
  namespace: orders
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
  namespace: orders
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
  namespace: orders
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
  kubectl -n orders rollout status "deployment/$d" --timeout=300s
done

echo "[capstone] orders ready:"
kubectl -n orders get pods
echo "[capstone] No VirtualService exists - that is the task."
