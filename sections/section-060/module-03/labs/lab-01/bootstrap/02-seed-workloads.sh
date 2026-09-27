#!/usr/bin/env bash
# gwapi-demo : where the Gateway lives, plus booking-service
# gwapi-team : a SEPARATE team's namespace with catalog-service, which must be
#              allowed to attach a route to the Gateway it does not own
# No Gateway and no HTTPRoute - that is the task.
set -euo pipefail

kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: gwapi-demo
  labels:
    istio-injection: enabled
---
apiVersion: v1
kind: Namespace
metadata:
  name: gwapi-team
  labels:
    istio-injection: enabled
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: booking-service-v1
  namespace: gwapi-demo
  labels:
    app: booking-service
spec:
  replicas: 1
  selector:
    matchLabels:
      app: booking-service
  template:
    metadata:
      labels:
        app: booking-service
    spec:
      containers:
        - name: booking-service
          image: mccutchen/go-httpbin:v2.15.0
          args: ["-port", "8080"]
          ports:
            - containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: booking-service
  namespace: gwapi-demo
spec:
  ports:
    - name: http
      port: 80
      targetPort: 8080
  selector:
    app: booking-service
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: catalog-service-v1
  namespace: gwapi-team
  labels:
    app: catalog-service
spec:
  replicas: 1
  selector:
    matchLabels:
      app: catalog-service
  template:
    metadata:
      labels:
        app: catalog-service
    spec:
      containers:
        - name: catalog-service
          image: mccutchen/go-httpbin:v2.15.0
          args: ["-port", "8080"]
          ports:
            - containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: catalog-service
  namespace: gwapi-team
spec:
  ports:
    - name: http
      port: 80
      targetPort: 8080
  selector:
    app: catalog-service
EOF

kubectl -n gwapi-demo rollout status deployment/booking-service-v1 --timeout=300s
kubectl -n gwapi-team rollout status deployment/catalog-service-v1 --timeout=300s

echo "[lab] Namespaces ready:"
kubectl get ns gwapi-demo gwapi-team --show-labels
kubectl -n gwapi-demo get svc
kubectl -n gwapi-team get svc
echo "[lab] No Gateway and no HTTPRoute exist - and therefore no gateway proxy at all."
