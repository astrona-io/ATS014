#!/usr/bin/env bash
# Creates the namespace `starfleet` (sidecar injection on) with the shuttle client
# and mesh-wide access logs, and the namespace `outpost` with the relay: a bare pod
# with no Service, so it is not in the mesh registry.
# astrona runs this script with KUBECONFIG pointed at the lab cluster.
set -euo pipefail
cd "$(dirname "$0")"

echo "==> Namespace and access logs"
kubectl apply -f manifests/namespace.yaml -f manifests/access-logs.yaml

echo "==> The shuttle"
kubectl apply -f manifests/shuttle.yaml

echo "==> The outpost namespace (relay, no Service)"
kubectl apply -f manifests/outpost.yaml

echo "==> Waiting for the pods (first run pulls images, takes a few minutes)"
kubectl wait -n starfleet --for=condition=Available deploy --all --timeout=600s
kubectl wait -n outpost --for=condition=Ready pod --all --timeout=600s
kubectl get pods -n starfleet
kubectl get pods -n outpost -o wide
