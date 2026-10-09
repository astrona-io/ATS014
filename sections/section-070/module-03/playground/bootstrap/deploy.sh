#!/usr/bin/env bash
# Deploy what the 070-03 playground needs (runs after install-istio.sh):
#   - namespace starfleet (sidecar injection) + mesh-wide access logs
#   - shuttle: the test client, with a sidecar
#   - freighter-vm-1 and freighter-vm-2: two pods WITHOUT a sidecar and
#     without a Service, standing in for virtual machines outside the mesh
# No WorkloadEntry, ServiceEntry or WorkloadGroup is created: writing them is
# the module.
set -euo pipefail

# Pin this playground's cluster: use a private kubeconfig, so nothing else that
# switches the global kubectl context meanwhile can redirect these commands.
KCFG="$(mktemp)"; trap 'rm -f "$KCFG"' EXIT
kubectl config view --minify --flatten --context "kind-astro-ats-014-playground-070-03" > "$KCFG"
export KUBECONFIG="$KCFG"
cd "$(dirname "$0")"

echo "==> Namespace and access logs"
kubectl apply -f manifests/namespace.yaml -f manifests/access-logs.yaml

echo "==> Shuttle and the two old freighters"
kubectl apply -f manifests/shuttle.yaml
kubectl apply -f manifests/freighter.yaml

echo "==> Waiting for pods (first run pulls images, takes a few minutes)"
kubectl wait -n starfleet --for=condition=Available deploy --all --timeout=600s

kubectl get pods -n starfleet -o wide
echo "==> Playground ats-014-playground-070-03 ready"
