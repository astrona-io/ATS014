#!/usr/bin/env bash
# locality-demo, single-node: locality is declared with the istio-locality pod
# label rather than derived from node topology.
#   zone-a - healthy, and the caller's own zone (tester is unlabelled, so it
#            takes the node's locality, which we set to zone-a)
#   zone-b - healthy, the failover target
# The LOCAL zone's backend is deliberately broken: it stays ready while
# returning 503 to everything, so only outlier detection can notice.
# No DestinationRule - that is the task.
set -euo pipefail

echo "[lab] Labelling the node as local/zone-a..."
for n in $(kubectl get nodes -o name); do
  kubectl label "$n" topology.kubernetes.io/region=local --overwrite
  kubectl label "$n" topology.kubernetes.io/zone=zone-a --overwrite
done

kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: locality-demo
  labels:
    istio-injection: enabled
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: always-503
  namespace: locality-demo
data:
  default.conf: |
    server {
      listen 8080;
      location / {
        return 503 "zone-a backend failure\n";
      }
    }
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: httpbin-zone-a
  namespace: locality-demo
  labels:
    app: httpbin
    zone: a
spec:
  replicas: 1
  selector:
    matchLabels:
      app: httpbin
      zone: a
  template:
    metadata:
      labels:
        app: httpbin
        zone: a
        istio-locality: local.zone-a
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
apiVersion: apps/v1
kind: Deployment
metadata:
  name: httpbin-zone-b
  namespace: locality-demo
  labels:
    app: httpbin
    zone: b
spec:
  replicas: 1
  selector:
    matchLabels:
      app: httpbin
      zone: b
  template:
    metadata:
      labels:
        app: httpbin
        zone: b
        istio-locality: local.zone-b
    spec:
      containers:
        - name: httpbin
          image: mccutchen/go-httpbin:v2.15.0
          args: ["-port", "8080"]
          ports:
            - containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: httpbin
  namespace: locality-demo
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
  namespace: locality-demo
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

for d in httpbin-zone-a httpbin-zone-b tester; do
  kubectl -n locality-demo rollout status "deployment/$d" --timeout=300s
done

echo "[lab] locality-demo ready. Both backends are 1/1 Running:"
kubectl -n locality-demo get pods -o wide
echo "[lab] zone-a is the caller's own locality AND it returns 503 to everything."
echo "[lab] No DestinationRule exists - that is the task."
