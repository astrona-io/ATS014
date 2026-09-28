#!/usr/bin/env bash
# checkout:
#   notification-service  v1 (["EMAIL"]) + v2 (["EMAIL","SMS"]) behind one Service
#   notification-shadow   a SEPARATE Service and Deployment, the mirror target
#   tester                client
# No VirtualService or DestinationRule - that is the task.
set -euo pipefail

kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: checkout
  labels:
    istio-injection: enabled
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: notification-service-v1
  namespace: checkout
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
  namespace: checkout
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
  namespace: checkout
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
  name: notification-shadow
  namespace: checkout
  labels:
    app: notification-shadow
spec:
  replicas: 1
  selector:
    matchLabels:
      app: notification-shadow
  template:
    metadata:
      labels:
        app: notification-shadow
    spec:
      containers:
        - name: notification-shadow
          image: nginx:1.27-alpine
          ports:
            - containerPort: 8084
          volumeMounts:
            - name: nginx-conf
              mountPath: /etc/nginx/conf.d
      volumes:
        - name: nginx-conf
          configMap:
            name: notification-shadow-v2-nginx-conf
---
apiVersion: v1
kind: Service
metadata:
  name: notification-shadow
  namespace: checkout
  labels:
    app: notification-shadow
spec:
  ports:
    - name: http
      port: 80
      targetPort: 8084
  selector:
    app: notification-shadow
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: tester
  namespace: checkout
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
  namespace: checkout
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
  namespace: checkout
data:
  default.conf: |
    server {
      listen 8084;
      location / {
        default_type application/json;
        return 200 '["EMAIL","SMS"]';
      }
    }
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: notification-shadow-v2-nginx-conf
  namespace: checkout
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

for d in notification-service-v1 notification-service-v2 notification-shadow tester; do
  kubectl -n checkout rollout status "deployment/$d" --timeout=300s
done

echo "[capstone] checkout ready:"
kubectl -n checkout get pods
echo "[capstone] No VirtualService and no DestinationRule exist - that is the task."
