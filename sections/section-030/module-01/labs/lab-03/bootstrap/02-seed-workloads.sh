#!/usr/bin/env bash
# Creates the namespace `starfleet` (sidecar injection on), mesh-wide access logs,
# the shuttle client and the probe pods: 3 probe-v1 pods and 1 probe-v2 pod
# behind one Service on port 8000.
# astrona runs this script with KUBECONFIG pointed at the lab cluster.
set -euo pipefail
cd "$(dirname "$0")"

echo "==> Namespace and access logs"
kubectl apply -f manifests/namespace.yaml -f manifests/access-logs.yaml

echo "==> The shuttle and the probe pods"
kubectl apply -f manifests/shuttle.yaml
kubectl apply -f manifests/probe.yaml

echo "==> Waiting for the deployments (first run pulls images, takes a few minutes)"
kubectl wait -n starfleet --for=condition=Available deploy --all --timeout=600s
kubectl get pods -n starfleet
