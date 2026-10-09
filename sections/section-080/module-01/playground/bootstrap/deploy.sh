#!/usr/bin/env bash
# Deploy what the 080-01 playground needs (runs after install-istio.sh):
#   - namespace starfleet (sidecar injection) + mesh-wide access logs
#   - shuttle, the test client every signal is sent from
# No ServiceEntry, Gateway, DestinationRule or VirtualService is created:
# writing them is the module. The mesh stays at its ALLOW_ANY default.
set -euo pipefail

# Pin this playground's cluster: use a private kubeconfig, so nothing else that
# switches the global kubectl context meanwhile can redirect these commands.
KCFG="$(mktemp)"; trap 'rm -f "$KCFG"' EXIT
kubectl config view --minify --flatten --context "kind-astro-ats-014-playground-080-01" > "$KCFG"
export KUBECONFIG="$KCFG"
cd "$(dirname "$0")"

echo "==> Namespace and access logs"
kubectl apply -f manifests/namespace.yaml -f manifests/access-logs.yaml

echo "==> Shuttle"
kubectl apply -f manifests/shuttle.yaml

echo "==> Waiting for pods (first run pulls images, takes a few minutes)"
kubectl wait -n starfleet --for=condition=Available deploy --all --timeout=600s

kubectl get pods -n starfleet
echo "==> Playground ats-014-playground-080-01 ready"
