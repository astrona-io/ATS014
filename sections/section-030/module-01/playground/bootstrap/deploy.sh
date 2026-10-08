#!/usr/bin/env bash
# Deploy what the section 030 module 01 playground needs (runs after install-istio.sh):
#   - namespace bookinfo (sidecar injection) + mesh-wide access logs
#   - curl client + httpbin v1/v2
#   - httpbin v1 scaled to 3 pods
set -euo pipefail

# Pin this lab's cluster: use a private kubeconfig, so nothing else that
# switches the global kubectl context meanwhile can redirect these commands.
KCFG="$(mktemp)"; trap 'rm -f "$KCFG"' EXIT
kubectl config view --minify --flatten --context "kind-astro-ats-014-playground-030-01" > "$KCFG"
export KUBECONFIG="$KCFG"
cd "$(dirname "$0")"

ISTIO_VERSION="${ISTIO_VERSION:-1.30.5}"

echo "==> Namespace and access logs"
kubectl apply -f manifests/namespace.yaml -f manifests/access-logs.yaml

echo "==> Test clients"
kubectl apply -f manifests/curl-client.yaml
kubectl apply -f manifests/httpbin.yaml

echo "==> Scale httpbin v1 to 3 pods"
kubectl scale -n bookinfo deploy/httpbin-v1 --replicas=3

echo "==> Waiting for pods (first run pulls images, takes a few minutes)"
kubectl wait -n bookinfo --for=condition=Available deploy --all --timeout=600s

kubectl get pods -n bookinfo
echo "==> Playground ats-014-playground-030-01 ready"
