#!/usr/bin/env bash
# Seeds the lab 000-01 starting state: one correctly meshed namespace, one
# namespace that was never labelled for injection, and one workload inside the
# meshed namespace that opted out with an annotation.
#
# Nothing here is broken in a way Kubernetes will report. Every pod is Running
# and every Service has endpoints. The fault is only visible to somebody who
# knows what an injected pod looks like.
set -euo pipefail

kubectl apply -f - <<'YAML'
apiVersion: v1
kind: Namespace
metadata:
  name: mesh-demo
  labels:
    istio-injection: enabled
---
# NOT labelled for injection. This is the first fault.
apiVersion: v1
kind: Namespace
metadata:
  name: legacy-app
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-nginx-conf
  namespace: mesh-demo
data:
  default.conf: |
    server {
      listen 8080;
      location / {
        default_type application/json;
        return 200 '{"service":"api","ok":true}';
      }
    }
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-nginx-conf
  namespace: legacy-app
data:
  default.conf: |
    server {
      listen 8080;
      location / {
        default_type application/json;
        return 200 '{"service":"billing","ok":true}';
      }
    }
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
  namespace: mesh-demo
  labels: {app: api}
spec:
  replicas: 1
  selector:
    matchLabels: {app: api}
  template:
    metadata:
      labels: {app: api}
    spec:
      containers:
        - name: api
          image: nginx:1.27-alpine
          ports: [{containerPort: 8080}]
          volumeMounts:
            - {name: nginx-conf, mountPath: /etc/nginx/conf.d}
      volumes:
        - name: nginx-conf
          configMap: {name: app-nginx-conf}
---
apiVersion: v1
kind: Service
metadata:
  name: api
  namespace: mesh-demo
  labels: {app: api}
spec:
  ports:
    - {name: http, port: 80, targetPort: 8080}
  selector: {app: api}
---
# In an injected namespace, but opted out with an annotation. Second fault.
apiVersion: apps/v1
kind: Deployment
metadata:
  name: reports
  namespace: mesh-demo
  labels: {app: reports}
spec:
  replicas: 1
  selector:
    matchLabels: {app: reports}
  template:
    metadata:
      labels: {app: reports}
      annotations:
        sidecar.istio.io/inject: "false"
    spec:
      containers:
        - name: reports
          image: curlimages/curl
          command: ["sh", "-c", "while true; do sleep 30; done"]
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: billing
  namespace: legacy-app
  labels: {app: billing}
spec:
  replicas: 1
  selector:
    matchLabels: {app: billing}
  template:
    metadata:
      labels: {app: billing}
    spec:
      containers:
        - name: billing
          image: nginx:1.27-alpine
          ports: [{containerPort: 8080}]
          volumeMounts:
            - {name: nginx-conf, mountPath: /etc/nginx/conf.d}
      volumes:
        - name: nginx-conf
          configMap: {name: app-nginx-conf}
---
apiVersion: v1
kind: Service
metadata:
  name: billing
  namespace: legacy-app
  labels: {app: billing}
spec:
  ports:
    - {name: http, port: 80, targetPort: 8080}
  selector: {app: billing}
YAML

for ns in mesh-demo legacy-app; do
  for d in $(kubectl -n "$ns" get deployment -o name); do
    kubectl -n "$ns" rollout status "$d" --timeout=180s
  done
done

echo "[lab] Starting state ready."
kubectl -n mesh-demo get pods
kubectl -n legacy-app get pods
