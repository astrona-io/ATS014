#!/usr/bin/env bash
# Reference solution, applied only by `astrona test` (the `testing:` block).
# `astrona run` never runs this, so students still do the work themselves.
# Kept in step with solution.md - if one changes, change the other.
set -euo pipefail

VM1=$(cat /tmp/vm1-ip); VM2=$(cat /tmp/vm2-ip)
kubectl apply -f - <<EOF
apiVersion: networking.istio.io/v1
kind: WorkloadEntry
metadata:
  name: legacy-vm-1
  namespace: vm-demo
spec:
  address: $VM1
  labels:
    app: legacy-backend
  serviceAccount: legacy-sa
---
apiVersion: networking.istio.io/v1
kind: WorkloadEntry
metadata:
  name: legacy-vm-2
  namespace: vm-demo
spec:
  address: $VM2
  labels:
    app: legacy-backend
  serviceAccount: legacy-sa
EOF

kubectl apply -f - <<'EOF'
apiVersion: networking.istio.io/v1
kind: ServiceEntry
metadata:
  name: legacy
  namespace: vm-demo
spec:
  hosts:
    - legacy.vm-demo.svc
  location: MESH_INTERNAL
  resolution: STATIC
  ports:
    - number: 8080
      name: http
      protocol: HTTP
  workloadSelector:
    labels:
      app: legacy-backend
EOF

kubectl apply -f - <<'EOF'
apiVersion: networking.istio.io/v1
kind: WorkloadGroup
metadata:
  name: legacy
  namespace: vm-demo
spec:
  metadata:
    labels:
      app: legacy-backend
  template:
    serviceAccount: legacy-sa
    ports:
      http: 8080
EOF

# Give istiod time to push this configuration to every proxy before the grader
# reads it back. By hand you spend longer than this reading the apply output;
# `astrona test` applies and grades in the same second, and would otherwise
# measure the previous state.
sleep 15
