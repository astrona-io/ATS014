#!/usr/bin/env bash
# Deploys what playground ats-014-playground-010-04 needs (runs after install-istio.sh):
#   - the namespaces starfleet and dock, both with sidecar injection, and mesh-wide access logs
#   - the probe v1 and v2 in starfleet, and its subsets in a DestinationRule
#   - a client pod in each namespace: shuttle (starfleet), patrol (starfleet, other labels) and shuttle (dock)
# No VirtualService is created: writing them is the module.
set -euo pipefail

# Pin this playground's cluster: use a private kubeconfig, so nothing else that
# switches the global kubectl context meanwhile can redirect these commands.
KCFG="$(mktemp)"; trap 'rm -f "$KCFG"' EXIT
kubectl config view --minify --flatten --context "kind-astro-ats-014-playground-010-04" > "$KCFG"
export KUBECONFIG="$KCFG"
cd "$(dirname "$0")"

echo "==> Namespaces and access logs"
kubectl apply -f manifests/namespace.yaml -f manifests/namespace-dock.yaml -f manifests/access-logs.yaml

echo "==> The probe and its subsets"
kubectl apply -f manifests/probe.yaml
kubectl apply -f manifests/destinationrule-probe.yaml

echo "==> The client pods"
kubectl apply -f manifests/shuttle.yaml -f manifests/patrol.yaml -f manifests/shuttle-dock.yaml

echo "==> Waiting for pods (first run pulls images, takes a few minutes)"
kubectl wait -n starfleet --for=condition=Available deploy --all --timeout=600s
kubectl wait -n dock --for=condition=Available deploy --all --timeout=600s

kubectl get pods -n starfleet
kubectl get pods -n dock
echo "==> Playground ats-014-playground-010-04 ready"
