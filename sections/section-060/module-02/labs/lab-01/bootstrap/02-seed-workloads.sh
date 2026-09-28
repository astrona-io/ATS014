#!/usr/bin/env bash
# k8s-ingress-demo: one backend to expose through the plain Kubernetes Ingress
# API, plus a self-signed key pair left on disk for the TLS half of the task.
# No Ingress and no IngressClass - that is the task.
set -euo pipefail

kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: k8s-ingress-demo
  labels:
    istio-injection: enabled
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: booking-service-v1
  namespace: k8s-ingress-demo
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
  namespace: k8s-ingress-demo
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
apiVersion: v1
kind: ConfigMap
metadata:
  name: booking-service-nginx-conf
  namespace: k8s-ingress-demo
data:
  default.conf: |
    server {
      listen 8080;
      location / {
        default_type application/json;
        return 200 '{"service":"booking-service"}';
      }
    }
EOF

kubectl -n k8s-ingress-demo rollout status deployment/booking-service-v1 --timeout=300s

echo "[lab] Generating a self-signed certificate for booking.ica.local..."
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /tmp/booking.key -out /tmp/booking.crt \
  -subj "/CN=booking.ica.local/O=ica" 2>/dev/null

echo "[lab] k8s-ingress-demo ready:"
kubectl -n k8s-ingress-demo get pods,svc
echo
echo "[lab] TLS material is at /tmp/booking.crt and /tmp/booking.key"
echo "[lab] Reach the gateway with a port-forward:"
echo "[lab]   kubectl -n istio-system port-forward svc/istio-ingressgateway 8080:80 &"
echo "[lab]   kubectl -n istio-system port-forward svc/istio-ingressgateway 8443:443 &"
echo "[lab] No Ingress and no IngressClass exist - that is the task."
