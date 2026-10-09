#!/usr/bin/env bash
# Creates the namespaces `starfleet` (shuttle, cargo) and `outpost` (probe v1/v2),
# both with sidecar injection, plus mesh-wide access logs.
# astrona runs this script with KUBECONFIG pointed at the lab cluster.
set -euo pipefail
cd "$(dirname "$0")"

echo "==> Namespaces and access logs"
kubectl apply -f manifests/namespace.yaml -f manifests/access-logs.yaml

echo "==> Shuttle and cargo on starfleet, probe on outpost"
kubectl apply -f manifests/shuttle.yaml
kubectl apply -f manifests/cargo.yaml
kubectl apply -f manifests/probe.yaml

echo "==> Waiting for the pods (first run pulls images, takes a few minutes)"
kubectl wait -n starfleet --for=condition=Available deploy --all --timeout=600s
kubectl wait -n outpost --for=condition=Available deploy --all --timeout=600s
kubectl get pods -n starfleet
kubectl get pods -n outpost
