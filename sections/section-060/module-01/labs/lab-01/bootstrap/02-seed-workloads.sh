#!/usr/bin/env bash
# ingress-demo: two backends that must be exposed on ONE gateway listener under
# different hostnames.
#   booking-service  answers /book
#   catalog-service  a second app, so host-based routing has something to do
# No Gateway and no VirtualService - that is the task.
set -euo pipefail

kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: ingress-demo
  labels:
    istio-injection: enabled
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: booking-service-v1
  namespace: ingress-demo
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
          image: nginx:1.27-alpine
          ports:
            - containerPort: 8080
          volumeMounts:
            - name: nginx-conf
              mountPath: /etc/nginx/conf.d
      volumes:
        - name: nginx-conf
          configMap:
            name: booking-service-nginx-conf
---
apiVersion: v1
kind: Service
metadata:
  name: booking-service
  namespace: ingress-demo
  labels:
    app: booking-service
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
  namespace: ingress-demo
  labels:
    app: catalog-service
    version: v1
spec:
  replicas: 1
  selector:
    matchLabels:
      app: catalog-service
      version: v1
  template:
    metadata:
      labels:
        app: catalog-service
        version: v1
    spec:
      containers:
        - name: catalog-service
          image: nginx:1.27-alpine
          ports:
            - containerPort: 8080
          volumeMounts:
            - name: nginx-conf
              mountPath: /etc/nginx/conf.d
      volumes:
        - name: nginx-conf
          configMap:
            name: catalog-service-nginx-conf
---
apiVersion: v1
kind: Service
metadata:
  name: catalog-service
  namespace: ingress-demo
  labels:
    app: catalog-service
spec:
  ports:
    - name: http
      port: 80
      targetPort: 8080
  selector:
    app: catalog-service
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: booking-service-nginx-conf
  namespace: ingress-demo
data:
  default.conf: |
    server {
      listen 8080;
      location / {
        default_type application/json;
        return 200 '{"service":"booking-service"}';
      }
    }
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: catalog-service-nginx-conf
  namespace: ingress-demo
data:
  default.conf: |
    server {
      listen 8080;
      location / {
        default_type application/json;
        return 200 '{"service":"catalog-service"}';
      }
    }
EOF

for d in booking-service-v1 catalog-service-v1; do
  kubectl -n ingress-demo rollout status "deployment/$d" --timeout=300s
done

echo "[lab] ingress-demo ready:"
kubectl -n ingress-demo get pods,svc
echo
echo "[lab] The ingress gateway is running but unconfigured."
echo "[lab] kind has no load balancer, so reach it with a port-forward:"
echo "[lab]   kubectl -n istio-system port-forward svc/istio-ingressgateway 8080:80 &"
echo "[lab] No Gateway and no VirtualService exist - that is the task."
