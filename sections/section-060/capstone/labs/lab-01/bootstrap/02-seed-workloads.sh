#!/usr/bin/env bash
# edge: three identical backends, each to be exposed through a DIFFERENT
# ingress API. A self-signed key pair is left on disk for the Ingress TLS half.
# No Gateway, Ingress, IngressClass, HTTPRoute or VirtualService - that is the task.
set -euo pipefail

make_app() {
  local name="$1"
  cat <<EOF
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${name}
  namespace: edge
  labels:
    app: ${name}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${name}
  template:
    metadata:
      labels:
        app: ${name}
    spec:
      containers:
        - name: app
          image: nginx:1.27-alpine
          ports:
            - containerPort: 8080
          volumeMounts:
            - name: nginx-conf
              mountPath: /etc/nginx/conf.d
      volumes:
        - name: nginx-conf
          configMap:
            name: ${name}-nginx-conf
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: ${name}-nginx-conf
  namespace: edge
data:
  default.conf: |
    server {
      listen 8080;
      location / {
        default_type application/json;
        return 200 '{"service":"${name}"}';
      }
    }
---
apiVersion: v1
kind: Service
metadata:
  name: ${name}
  namespace: edge
spec:
  ports:
    - name: http
      port: 80
      targetPort: 8080
  selector:
    app: ${name}
EOF
}

{
  cat <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: edge
  labels:
    istio-injection: enabled
EOF
  make_app native-app
  make_app legacy-app
  make_app modern-app
} | kubectl apply -f -

for d in native-app legacy-app modern-app; do
  kubectl -n edge rollout status "deployment/$d" --timeout=300s
done

echo "[capstone] Generating a self-signed certificate for legacy.ica.local..."
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /tmp/legacy.key -out /tmp/legacy.crt \
  -subj "/CN=legacy.ica.local/O=ica" 2>/dev/null

echo "[capstone] edge namespace ready:"
kubectl -n edge get pods,svc
echo
echo "[capstone] TLS material: /tmp/legacy.crt and /tmp/legacy.key"
echo "[capstone] No ingress configuration of any kind exists - that is the task."
