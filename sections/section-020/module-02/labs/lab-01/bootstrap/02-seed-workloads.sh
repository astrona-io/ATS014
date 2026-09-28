#!/usr/bin/env bash
# mirror-demo: a stable v1 and a shadow candidate v2 behind one Service, plus a
# tester client. v1 answers ["EMAIL"], v2 answers ["EMAIL","SMS"].
# No VirtualService or DestinationRule - that is the task.
set -euo pipefail

kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: mirror-demo
  labels:
    istio-injection: enabled
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: notification-service-v1
  namespace: mirror-demo
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
apiVersion: apps/v1
kind: Deployment
metadata:
  name: notification-service-v2
  namespace: mirror-demo
  labels:
    app: notification-service
    version: v2
spec:
  replicas: 1
  selector:
    matchLabels:
      app: notification-service
      version: v2
  template:
    metadata:
      labels:
        app: notification-service
        version: v2
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
            name: notification-service-v2-nginx-conf
---
apiVersion: v1
kind: Service
metadata:
  name: notification-service
  namespace: mirror-demo
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
  name: tester
  namespace: mirror-demo
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
apiVersion: v1
kind: ConfigMap
metadata:
  name: notification-service-v1-nginx-conf
  namespace: mirror-demo
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
apiVersion: v1
kind: ConfigMap
metadata:
  name: notification-service-v2-nginx-conf
  namespace: mirror-demo
data:
  default.conf: |
    server {
      listen 8084;
      location / {
        default_type application/json;
        return 200 '["EMAIL","SMS"]';
      }
    }
EOF

for d in notification-service-v1 notification-service-v2 tester; do
  kubectl -n mirror-demo rollout status "deployment/$d" --timeout=300s
done

echo "[lab] mirror-demo ready:"
kubectl -n mirror-demo get pods
echo "[lab] No VirtualService and no DestinationRule exist - that is the task."
