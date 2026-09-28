#!/usr/bin/env bash
# vm-demo: an injected client, a ServiceAccount for the VM identity, and TWO
# uninjected pods standing in for virtual machines - reachable by address,
# unknown to the mesh, and with no Service in front of them.
set -euo pipefail

kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: vm-demo
  labels:
    istio-injection: enabled
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: legacy-sa
  namespace: vm-demo
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: tester
  namespace: vm-demo
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
kind: Pod
metadata:
  name: legacy-vm-1
  namespace: vm-demo
  labels:
    role: standin-vm
    sidecar.istio.io/inject: "false"
spec:
  serviceAccountName: legacy-sa
  containers:
    - name: app
      image: mccutchen/go-httpbin:v2.15.0
      command: ["/bin/go-httpbin", "-port", "8080"]
      ports:
        - containerPort: 8080
---
apiVersion: v1
kind: Pod
metadata:
  name: legacy-vm-2
  namespace: vm-demo
  labels:
    role: standin-vm
    sidecar.istio.io/inject: "false"
spec:
  serviceAccountName: legacy-sa
  containers:
    - name: app
      image: mccutchen/go-httpbin:v2.15.0
      command: ["/bin/go-httpbin", "-port", "8080"]
      ports:
        - containerPort: 8080
EOF

kubectl -n vm-demo rollout status deployment/tester --timeout=300s
kubectl -n vm-demo wait --for=condition=Ready pod/legacy-vm-1 --timeout=300s
kubectl -n vm-demo wait --for=condition=Ready pod/legacy-vm-2 --timeout=300s

VM1=$(kubectl -n vm-demo get pod legacy-vm-1 -o jsonpath='{.status.podIP}')
VM2=$(kubectl -n vm-demo get pod legacy-vm-2 -o jsonpath='{.status.podIP}')
printf '%s' "$VM1" > /tmp/vm1-ip
printf '%s' "$VM2" > /tmp/vm2-ip

echo
echo "[lab] Two stand-in virtual machines (uninjected, no Service):"
echo "[lab]   legacy-vm-1  ${VM1}:8080"
echo "[lab]   legacy-vm-2  ${VM2}:8080"
echo "[lab] Addresses are also in /tmp/vm1-ip and /tmp/vm2-ip"
echo "[lab] Note they run as ServiceAccount legacy-sa and have NO sidecar (1/1):"
kubectl -n vm-demo get pods -o wide
echo "[lab] No WorkloadEntry, ServiceEntry or WorkloadGroup exists - that is the task."
