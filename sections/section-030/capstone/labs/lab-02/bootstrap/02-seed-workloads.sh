#!/usr/bin/env bash
# Creates the namespace `starfleet` (sidecar injection on) with mesh-wide access
# logs, the shuttle client and the probe pods (3 v1 pods and 2 v2 pods behind
# one Service on port 8000), and the namespace `outpost` (no injection) with the
# drifter, a client with no sidecar proxy.
# astrona runs this script with KUBECONFIG pointed at the lab cluster.
set -euo pipefail
cd "$(dirname "$0")"

echo "==> Namespaces and access logs"
kubectl apply -f manifests/namespace.yaml -f manifests/access-logs.yaml

echo "==> The shuttle, the probe and the drifter"
kubectl apply -f manifests/shuttle.yaml
kubectl apply -f manifests/probe.yaml
kubectl apply -f manifests/outpost.yaml

echo "==> Waiting for the deployments (first run pulls images, takes a few minutes)"
kubectl wait -n starfleet --for=condition=Available deploy --all --timeout=600s
kubectl wait -n outpost --for=condition=Available deploy --all --timeout=600s
kubectl get pods -n starfleet
kubectl get pods -n outpost
