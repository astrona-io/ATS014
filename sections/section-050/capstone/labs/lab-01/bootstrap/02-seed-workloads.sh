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
          image: nginx:1.27-alpine
          ports:
            - containerPort: 8083
          volumeMounts:
            - name: nginx-conf
              mountPath: /etc/nginx/conf.d
      volumes:
        - name: nginx-conf
          configMap:
            name: booking-service-v1-nginx-conf
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
          image: nginx:1.27-alpine
          ports:
            - containerPort: 8084
          volumeMounts:
            - name: nginx-conf
              mountPath: /etc/nginx/conf.d
      volumes:
        - name: nginx-conf
          configMap:
            name: notification-service-v1-nginx-conf
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
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: booking-service-v1-nginx-conf
  namespace: orders
data:
  default.conf: |
    server {
      listen 8083;
      location / {
        proxy_pass http://notification-service:80/notify;
        proxy_http_version 1.1;
        # No proxy_set_header Host here on purpose: nginx then sends the
        # upstream's own name as the authority. Keeping the caller's Host
        # would make the sidecar route the hop straight back to this service,
        # because Istio routes on the authority header.
      }
    }
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: notification-service-v1-nginx-conf
  namespace: orders
data:
  default.conf: |
    server {
      listen 8084;
      location / {
        default_type application/json;
        return 200 '["EMAIL"]';
      }
    }
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: tester
  namespace: orders
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

for d in booking-service-v1 notification-service-v1 tester; do
  kubectl -n orders rollout status "deployment/$d" --timeout=300s
done

echo "[capstone] orders ready:"
kubectl -n orders get pods
echo "[capstone] No VirtualService exists - that is the task."
