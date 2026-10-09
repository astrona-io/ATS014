#!/usr/bin/env bash
# Deploy what the Fault Injection playground needs (runs after install-istio.sh):
#   - namespace starfleet (sidecar injection) + mesh-wide access logs
#   - the Starfleet: bridge, cargo, scout v1-v3, navcom (scout v2 and v3 call navcom)
#   - shuttle (test client) + probe v1/v2 (echo service)
#   - the scout subsets (v1, v2, v3) and the navcom subset (v1)
# No flight plan (VirtualService) is created: writing them is the module.
set -euo pipefail

# Pin this playground's cluster: use a private kubeconfig, so nothing else that
# switches the global kubectl context meanwhile can redirect these commands.
KCFG="$(mktemp)"; trap 'rm -f "$KCFG"' EXIT
kubectl config view --minify --flatten --context "kind-astro-ats-014-playground-050-01" > "$KCFG"
export KUBECONFIG="$KCFG"
cd "$(dirname "$0")"

echo "==> Namespace and access logs"
kubectl apply -f manifests/namespace.yaml -f manifests/access-logs.yaml

echo "==> The Starfleet"
kubectl apply -n starfleet -f manifests/starfleet.yaml

echo "==> Shuttle and probe"
kubectl apply -f manifests/shuttle.yaml
kubectl apply -f manifests/probe.yaml

echo "==> Scout and navcom subsets"
kubectl apply -f manifests/scout-subsets.yaml
kubectl apply -f manifests/navcom-subsets.yaml

echo "==> Waiting for pods (first run pulls images, takes a few minutes)"
kubectl wait -n starfleet --for=condition=Available deploy --all --timeout=600s

kubectl get pods -n starfleet
echo "==> Playground ats-014-playground-050-01 ready"
