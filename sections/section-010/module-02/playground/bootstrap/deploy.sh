#!/usr/bin/env bash
# Deploy what the 010-02 playground needs (runs after install-istio.sh):
#   - namespaces starfleet and outpost (sidecar injection) + mesh-wide access logs
#   - starfleet: shuttle (test client) and cargo (a local service on port 9080)
#   - outpost:   probe v1/v2 (echo service on port 8000)
# No Sidecar resource is created: writing one is the module.
set -euo pipefail

# Pin this playground's cluster: use a private kubeconfig, so nothing else that
# switches the global kubectl context meanwhile can redirect these commands.
KCFG="$(mktemp)"; trap 'rm -f "$KCFG"' EXIT
kubectl config view --minify --flatten --context "kind-astro-ats-014-playground-010-02" > "$KCFG"
export KUBECONFIG="$KCFG"
cd "$(dirname "$0")"

echo "==> Namespaces and access logs"
kubectl apply -f manifests/namespace.yaml -f manifests/access-logs.yaml

echo "==> Shuttle and cargo on starfleet, probe on outpost"
kubectl apply -f manifests/shuttle.yaml
kubectl apply -f manifests/cargo.yaml
kubectl apply -f manifests/probe.yaml

echo "==> Waiting for pods (first run pulls images, takes a few minutes)"
kubectl wait -n starfleet --for=condition=Available deploy --all --timeout=600s
kubectl wait -n outpost --for=condition=Available deploy --all --timeout=600s

kubectl get pods -n starfleet
kubectl get pods -n outpost
echo "==> Playground ats-014-playground-010-02 ready"
