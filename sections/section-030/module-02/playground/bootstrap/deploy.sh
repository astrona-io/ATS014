#!/usr/bin/env bash
# Deploy what the section 030 module 02 playground needs (runs after install-istio.sh):
#   - namespace starfleet (sidecar injection) + mesh-wide access logs
#   - shuttle (test client, with a sidecar proxy)
#   - probe v1 (3 pods) and v2 (1 pod) behind one Service on port 8000
#   - namespace outpost (no injection) with the drifter: a client with no sidecar proxy
# No PeerAuthentication and no DestinationRule is created: the module does that.
set -euo pipefail

# Pin this playground's cluster: use a private kubeconfig, so nothing else that
# switches the global kubectl context meanwhile can redirect these commands.
KCFG="$(mktemp)"; trap 'rm -f "$KCFG"' EXIT
kubectl config view --minify --flatten --context "kind-astro-ats-014-playground-030-02" > "$KCFG"
export KUBECONFIG="$KCFG"
cd "$(dirname "$0")"

echo "==> Namespaces and access logs"
kubectl apply -f manifests/namespace.yaml -f manifests/access-logs.yaml

echo "==> Shuttle and probe (in the mesh)"
kubectl apply -f manifests/shuttle.yaml
kubectl apply -f manifests/probe.yaml

echo "==> Drifter (outside the mesh)"
kubectl apply -f manifests/outpost.yaml

echo "==> Waiting for pods (first run pulls images, takes a few minutes)"
kubectl wait -n starfleet --for=condition=Available deploy --all --timeout=600s
kubectl wait -n outpost --for=condition=Available deploy --all --timeout=600s

kubectl get pods -n starfleet
kubectl get pods -n outpost
echo "==> Playground ats-014-playground-030-02 ready"
