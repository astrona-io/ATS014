#!/usr/bin/env bash
# outlier-demo: two endpoints behind one Service.
#   httpbin-good - answers normally
#   httpbin-bad  - nginx returning 503 to EVERYTHING, while passing readiness
# That second pod is the point: Kubernetes considers it healthy.
# No DestinationRule - that is the task.
set -euo pipefail

kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: outlier-demo
  labels:
    istio-injection: enabled
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: always-503
  namespace: outlier-demo
data:
  default.conf: |
    server {
      listen 8080;
      location / {
        return 503 "simulated backend failure\n";
      }
    }
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: httpbin-good
  namespace: outlier-demo
  labels:
    app: httpbin
    health: good
spec:
  replicas: 1
  selector:
    matchLabels:
      app: httpbin
      health: good
  template:
    metadata:
      labels:
        app: httpbin
        health: good
    spec:
      containers:
        - name: httpbin
          image: mccutchen/go-httpbin:v2.15.0
          command: ["/bin/go-httpbin", "-port", "8080"]
          ports:
            - containerPort: 8080
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: httpbin-bad
  namespace: outlier-demo
  labels:
    app: httpbin
    health: bad
spec:
  replicas: 1
  selector:
    matchLabels:
      app: httpbin
      health: bad
  template:
    metadata:
      labels:
        app: httpbin
        health: bad
    spec:
      containers:
        - name: httpbin
          image: nginx:1.27-alpine
          ports:
            - containerPort: 8080
          volumeMounts:
            - name: conf
              mountPath: /etc/nginx/conf.d
      volumes:
        - name: conf
          configMap:
            name: always-503
---
apiVersion: v1
kind: Service
metadata:
  name: httpbin
  namespace: outlier-demo
  labels:
    app: httpbin
spec:
  ports:
    - name: http
      port: 8000
      targetPort: 8080
  selector:
    app: httpbin
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: tester
  namespace: outlier-demo
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

for d in httpbin-good httpbin-bad tester; do
  kubectl -n outlier-demo rollout status "deployment/$d" --timeout=300s
done

echo "[lab] outlier-demo ready - note BOTH pods are 1/1 Running:"
kubectl -n outlier-demo get pods -o wide
echo "[lab] No DestinationRule exists - roughly half of all traffic fails."
