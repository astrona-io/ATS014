#!/usr/bin/env bash
# Deploy what the 010-01 playground needs (runs after install-istio.sh):
#   - namespace bookinfo (sidecar injection) + mesh-wide access logs
#   - Bookinfo (productpage, details, reviews v1-v3, ratings)
#   - curl client + httpbin v1/v2 (httpbin is used by parts 4 and 5:
#     it echoes headers and paths, and its port can be renamed to "tcp")
# No DestinationRule or VirtualService is created: writing them is the module.
set -euo pipefail

# Pin this playground's cluster: use a private kubeconfig, so nothing else that
# switches the global kubectl context meanwhile can redirect these commands.
KCFG="$(mktemp)"; trap 'rm -f "$KCFG"' EXIT
kubectl config view --minify --flatten --context "kind-astro-ats-014-playground-010-01" > "$KCFG"
export KUBECONFIG="$KCFG"
cd "$(dirname "$0")"

ISTIO_VERSION="${ISTIO_VERSION:-1.30.5}"

echo "==> Namespace and access logs"
kubectl apply -f manifests/namespace.yaml -f manifests/access-logs.yaml

echo "==> Bookinfo"
BRANCH="release-${ISTIO_VERSION%.*}"   # 1.30.5 -> release-1.30
kubectl apply -n bookinfo -f "https://raw.githubusercontent.com/istio/istio/$BRANCH/samples/bookinfo/platform/kube/bookinfo.yaml"

echo "==> Test clients"
kubectl apply -f manifests/curl-client.yaml
kubectl apply -f manifests/httpbin.yaml

echo "==> Waiting for pods (first run pulls images, takes a few minutes)"
kubectl wait -n bookinfo --for=condition=Available deploy --all --timeout=600s

kubectl get pods -n bookinfo
echo "==> Playground ats-014-playground-010-01 ready"
