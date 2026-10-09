#!/usr/bin/env bash
# The starting state: a third probe ship that answers every signal with 503,
# behind the same `probe` Service, and no DestinationRule at all.
# astrona runs this script with KUBECONFIG pointed at the lab cluster.
set -euo pipefail

kubectl apply -f - <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: probe-broken
  namespace: starfleet
spec:
  replicas: 1
  selector:
    matchLabels:
      app: probe
      version: broken
  template:
    metadata:
      labels:
        app: probe
        version: broken
    spec:
      containers:
      - name: http-echo
        image: hashicorp/http-echo:1.0
        args: ["-listen=:8080", "-status-code=503", "-text=broken"]
        ports:
        - containerPort: 8080
YAML

kubectl rollout status -n starfleet deploy/probe-broken --timeout=300s
kubectl get pods -n starfleet -l app=probe
