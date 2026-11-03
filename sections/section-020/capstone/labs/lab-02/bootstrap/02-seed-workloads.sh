#!/usr/bin/env bash
# Creates the namespace `starfleet` (sidecar injection on), mesh-wide access logs,
# the probe in two versions (v1, v2) with its HTTP Service (probe) and its TCP
# Service (probe-tcp), a separate probe-shadow Deployment and Service, and the
# shuttle client. No DestinationRule and no VirtualService.
# astrona runs this script with KUBECONFIG pointed at the lab cluster.
set -euo pipefail
cd "$(dirname "$0")"

echo "==> Namespace and access logs"
kubectl apply -f manifests/namespace.yaml -f manifests/access-logs.yaml

echo "==> The probe, its two Services, the shadow and the shuttle"
kubectl apply -f manifests/probe.yaml
kubectl apply -f manifests/probe-tcp.yaml
kubectl apply -f manifests/probe-shadow.yaml
kubectl apply -f manifests/shuttle.yaml

echo "==> Waiting for the deployments (first run pulls images, takes a few minutes)"
kubectl wait -n starfleet --for=condition=Available deploy --all --timeout=600s
kubectl get pods -n starfleet
