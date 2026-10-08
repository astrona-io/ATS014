#!/usr/bin/env bash
# Deploy what playground ats-014-playground-020-02 needs (runs after install-istio.sh):
#   - namespace starfleet (sidecar injection) + mesh-wide access logs
#   - shuttle (test client) + probe v1/v2 (echo service)
set -euo pipefail

# Pin this lab's cluster: use a private kubeconfig, so nothing else that
# switches the global kubectl context meanwhile can redirect these commands.
KCFG="$(mktemp)"; trap 'rm -f "$KCFG"' EXIT
kubectl config view --minify --flatten --context "kind-astro-ats-014-playground-020-02" > "$KCFG"
export KUBECONFIG="$KCFG"
cd "$(dirname "$0")"

ISTIO_VERSION="${ISTIO_VERSION:-1.30.5}"

echo "==> Namespace and access logs"
kubectl apply -f manifests/namespace.yaml -f manifests/access-logs.yaml

echo "==> Shuttle and probe"
kubectl apply -f manifests/shuttle.yaml
kubectl apply -f manifests/probe.yaml

echo "==> Waiting for pods (first run pulls images, takes a few minutes)"
kubectl wait -n starfleet --for=condition=Available deploy --all --timeout=600s

kubectl get pods -n starfleet
echo "==> Playground ats-014-playground-020-02 ready"
