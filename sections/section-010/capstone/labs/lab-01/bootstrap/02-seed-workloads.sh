#!/usr/bin/env bash
# storefront : two versions of catalog behind one Service, plus a shopper client.
#              v1 answers ["EMAIL"] and v2 answers ["EMAIL","SMS"] on POST /notify,
#              which is how you (and the grader) tell which version served a request.
# partners   : a backend storefront legitimately calls
# archive    : a backend nobody calls, which must end up scoped out
# No VirtualService, DestinationRule or Sidecar is created - that is the task.
set -euo pipefail

kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: storefront
  labels:
    istio-injection: enabled
---
apiVersion: v1
kind: Namespace
metadata:
  name: partners
  labels:
    istio-injection: enabled
---
apiVersion: v1
kind: Namespace
metadata:
  name: archive
  labels:
    istio-injection: enabled
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: catalog-v1
  namespace: storefront
  labels:
    app: catalog
    version: v1
spec:
  replicas: 1
  selector:
    matchLabels:
      app: catalog
      version: v1
  template:
    metadata:
      labels:
        app: catalog
        version: v1
    spec:
      containers:
        - name: catalog
          image: kubeteam/notification-service:v1
          ports:
            - containerPort: 8084
          env:
            - name: SERVICE_PORT
              value: "8084"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: catalog-v2
  namespace: storefront
  labels:
    app: catalog
    version: v2
spec:
  replicas: 1
  selector:
    matchLabels:
      app: catalog
      version: v2
  template:
    metadata:
      labels:
        app: catalog
        version: v2
    spec:
      containers:
        - name: catalog
          image: kubeteam/notification-service:v2
          ports:
            - containerPort: 8084
          env:
            - name: SERVICE_PORT
              value: "8084"
---
apiVersion: v1
kind: Service
metadata:
  name: catalog
  namespace: storefront
  labels:
    app: catalog
spec:
  ports:
    - name: http
      port: 8000
      targetPort: 8084
  selector:
    app: catalog
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: shopper
  namespace: storefront
  labels:
    app: shopper
spec:
  replicas: 1
  selector:
    matchLabels:
      app: shopper
  template:
    metadata:
      labels:
        app: shopper
    spec:
      containers:
        - name: shopper
          image: curlimages/curl
          command: ["sh", "-c", "while true; do sleep 30; done"]
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pricing
  namespace: partners
  labels:
    app: pricing
spec:
  replicas: 1
  selector:
    matchLabels:
      app: pricing
  template:
    metadata:
      labels:
        app: pricing
    spec:
      containers:
        - name: pricing
          image: mccutchen/go-httpbin:v2.15.0
          args: ["-port", "8080"]
          ports:
            - containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: pricing
  namespace: partners
spec:
  ports:
    - name: http
      port: 8000
      targetPort: 8080
  selector:
    app: pricing
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: coldstore
  namespace: archive
  labels:
    app: coldstore
spec:
  replicas: 1
  selector:
    matchLabels:
      app: coldstore
  template:
    metadata:
      labels:
        app: coldstore
    spec:
      containers:
        - name: coldstore
          image: mccutchen/go-httpbin:v2.15.0
          args: ["-port", "8080"]
          ports:
            - containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: coldstore
  namespace: archive
spec:
  ports:
    - name: http
      port: 8000
      targetPort: 8080
  selector:
    app: coldstore
EOF

kubectl -n storefront rollout status deployment/catalog-v1 --timeout=300s
kubectl -n storefront rollout status deployment/catalog-v2 --timeout=300s
kubectl -n storefront rollout status deployment/shopper   --timeout=300s
kubectl -n partners   rollout status deployment/pricing   --timeout=300s
kubectl -n archive    rollout status deployment/coldstore --timeout=300s

echo "[capstone] Namespaces ready:"
kubectl get pods -A -l 'app in (catalog,shopper,pricing,coldstore)'
echo "[capstone] No VirtualService, DestinationRule or Sidecar exists - that is the task."
