#!/usr/bin/env bash
# Creates the namespace `starfleet` (sidecar injection on), mesh-wide access logs,
# the echo probe (v1 and v2 behind one Service on port 8000) and the shuttle client.
# astrona runs this script with KUBECONFIG pointed at the lab cluster.
set -euo pipefail
cd "$(dirname "$0")"

echo "==> Namespace and access logs"
kubectl apply -f manifests/namespace.yaml -f manifests/access-logs.yaml

echo "==> The echo probe and the shuttle"
kubectl apply -f manifests/probe.yaml -f manifests/shuttle.yaml

echo "==> Waiting for the pods (first run pulls images, takes a few minutes)"
kubectl wait -n starfleet --for=condition=Available deploy --all --timeout=600s
kubectl get pods -n starfleet
