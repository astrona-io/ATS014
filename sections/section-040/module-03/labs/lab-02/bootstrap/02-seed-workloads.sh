#!/usr/bin/env bash
# Creates the planet `starfleet` (sidecar injection on), mesh-wide access logs,
# the probe (v1 and v2), the shuttle client and the fortio load generator.
# astrona runs this script with KUBECONFIG pointed at the lab cluster.
set -euo pipefail
cd "$(dirname "$0")"

echo "==> Namespace and access logs"
kubectl apply -f manifests/namespace.yaml -f manifests/access-logs.yaml

echo "==> Probe, shuttle and fortio"
kubectl apply -f manifests/probe.yaml
kubectl apply -f manifests/shuttle.yaml
kubectl apply -f manifests/fortio.yaml

echo "==> Waiting for the ships (first run pulls images, takes a few minutes)"
kubectl wait -n starfleet --for=condition=Available deploy --all --timeout=600s
kubectl get pods -n starfleet
