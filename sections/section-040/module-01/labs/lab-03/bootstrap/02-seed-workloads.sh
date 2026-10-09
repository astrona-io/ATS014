#!/usr/bin/env bash
# Creates the namespace `starfleet` (sidecar injection on), mesh-wide access logs,
# the probe v1/v2 (an echo service that answers any status code on demand) and
# the shuttle client. astrona runs this script with KUBECONFIG pointed at the lab.
set -euo pipefail
cd "$(dirname "$0")"

echo "==> Namespace and access logs"
kubectl apply -f manifests/namespace.yaml -f manifests/access-logs.yaml

echo "==> The probe and the shuttle"
kubectl apply -f manifests/probe.yaml
kubectl apply -f manifests/shuttle.yaml

echo "==> Waiting for the deployments"
kubectl wait -n starfleet --for=condition=Available deploy --all --timeout=600s
kubectl get pods -n starfleet
