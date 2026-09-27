#!/usr/bin/env bash
# payments:
#   ledger-good - 2 replicas, healthy, /delay and /status endpoints
#   ledger-bad  - 1 replica returning 503 to everything while staying ready
#   ledger      - one Service on port 8000 in front of all three
#   fortio      - load generator (curl is sequential; concurrency matters here)
# No VirtualService or DestinationRule - that is the task.
set -euo pipefail

echo "[capstone] Labelling the node as local/zone-a..."
for n in $(kubectl get nodes -o name); do
  kubectl label "$n" topology.kubernetes.io/region=local --overwrite
  kubectl label "$n" topology.kubernetes.io/zone=zone-a --overwrite
done

kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: payments
  labels:
    istio-injection: enabled
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: always-503
  namespace: payments
data:
  default.conf: |
    server {
      listen 8080;
      location / {
        return 503 "ledger replica failure\n";
      }
    }
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ledger-good
  namespace: payments
  labels:
    app: ledger
    health: good
spec:
  replicas: 2
  selector:
    matchLabels:
      app: ledger
      health: good
  template:
    metadata:
      labels:
        app: ledger
        health: good
    spec:
      containers:
        - name: ledger
          image: mccutchen/go-httpbin:v2.15.0
          args: ["-port", "8080"]
          ports:
            - containerPort: 8080
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ledger-bad
  namespace: payments
  labels:
    app: ledger
    health: bad
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ledger
      health: bad
  template:
    metadata:
      labels:
        app: ledger
        health: bad
    spec:
      containers:
        - name: ledger
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
  name: ledger
  namespace: payments
  labels:
    app: ledger
spec:
  ports:
    - name: http
      port: 8000
      targetPort: 8080
  selector:
    app: ledger
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fortio
  namespace: payments
  labels:
    app: fortio
spec:
  replicas: 1
  selector:
    matchLabels:
      app: fortio
  template:
    metadata:
      labels:
        app: fortio
    spec:
      containers:
        - name: fortio
          image: fortio/fortio:latest_release
          ports:
            - containerPort: 8080
EOF

for d in ledger-good ledger-bad fortio; do
  kubectl -n payments rollout status "deployment/$d" --timeout=300s
done

echo "[capstone] payments ready - all three ledger pods are Running and Ready:"
kubectl -n payments get pods -o wide
echo "[capstone] No VirtualService and no DestinationRule exist - that is the task."
