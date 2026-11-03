#!/usr/bin/env bash
# Creates the namespace `starfleet` (sidecar injection on), mesh-wide access logs,
# the probe v1 and v2 with its subsets (a DestinationRule), and the shuttle client.
# No VirtualService exists: writing them is the task.
# astrona runs this script with KUBECONFIG pointed at the lab cluster.
set -euo pipefail
cd "$(dirname "$0")"

echo "==> Namespace and access logs"
kubectl apply -f manifests/namespace.yaml -f manifests/access-logs.yaml

echo "==> The probe, its subsets and the shuttle"
kubectl apply -f manifests/probe.yaml
kubectl apply -f manifests/destinationrule-probe.yaml
kubectl apply -f manifests/shuttle.yaml

echo "==> Waiting for the pods (first run pulls images, takes a few minutes)"
kubectl wait -n starfleet --for=condition=Available deploy --all --timeout=600s
kubectl get pods -n starfleet
echo "==> Lab ats-014-lab-010-04-01 ready"
