#!/usr/bin/env bash
# Deploy what the 060-02 playground needs (runs after install-istio.sh):
#   - namespace starfleet (sidecar injection) + mesh-wide access logs
#   - the Starfleet: bridge, cargo, scout v1-v3, navcom (Bookinfo with space names)
#   - shuttle (test client) + probe v1/v2 (echo service: it answers any path
#     under /anything, so a 404 can only come from the gateway)
# No IngressClass and no Ingress are created: writing them is the module.
set -euo pipefail

# Pin this playground's cluster: use a private kubeconfig, so nothing else that
# switches the global kubectl context meanwhile can redirect these commands.
KCFG="$(mktemp)"; trap 'rm -f "$KCFG"' EXIT
kubectl config view --minify --flatten --context "kind-astro-ats-014-playground-060-02" > "$KCFG"
export KUBECONFIG="$KCFG"
cd "$(dirname "$0")"

echo "==> Namespace and access logs"
kubectl apply -f manifests/namespace.yaml -f manifests/access-logs.yaml

echo "==> The Starfleet"
kubectl apply -n starfleet -f manifests/starfleet.yaml

echo "==> Shuttle and probe"
kubectl apply -f manifests/shuttle.yaml
kubectl apply -f manifests/probe.yaml

echo "==> Waiting for pods (first run pulls images, takes a few minutes)"
kubectl wait -n starfleet --for=condition=Available deploy --all --timeout=600s

kubectl get pods -n starfleet
echo "==> Playground ats-014-playground-060-02 ready"
