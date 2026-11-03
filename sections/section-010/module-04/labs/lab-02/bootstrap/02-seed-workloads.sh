#!/usr/bin/env bash
# Creates three namespaces with sidecar injection (starfleet, dock and depot),
# mesh-wide access logs, the probe v1 and v2 in starfleet, and a shuttle client
# pod in each namespace.
# astrona runs this script with KUBECONFIG pointed at the lab cluster.
set -euo pipefail
cd "$(dirname "$0")"

echo "==> Namespaces and access logs"
kubectl apply -f manifests/namespace.yaml -f manifests/namespace-dock.yaml \
  -f manifests/namespace-depot.yaml -f manifests/access-logs.yaml

echo "==> The probe"
kubectl apply -f manifests/probe.yaml

echo "==> The shuttle in each namespace"
kubectl apply -f manifests/shuttle.yaml -f manifests/shuttle-dock.yaml -f manifests/shuttle-depot.yaml

echo "==> Waiting for the pods (first run pulls images, takes a few minutes)"
for namespace in starfleet dock depot; do
  kubectl wait -n "$namespace" --for=condition=Available deploy --all --timeout=600s
done
kubectl get pods -A -l 'app in (probe,shuttle)'
echo "==> Lab ats-014-lab-010-04-02 workloads ready"
