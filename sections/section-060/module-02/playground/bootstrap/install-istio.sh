#!/usr/bin/env bash
# Install Istio (sidecar mode) into this playground's kind cluster with Helm:
#   istio-system   istio-base (CRDs), istiod (control plane) and the ingress
#                  gateway, released as "istio-ingressgateway" so its pods carry
#                  the label istio=ingressgateway.
# That name and label are what istiod looks for by default when it serves a
# Kubernetes Ingress (mesh settings ingressService / ingressSelector), so no
# extra mesh configuration is needed.
# Change the version with:  ISTIO_VERSION=<version> astrona run -c .
set -euo pipefail

# Pin this playground's cluster: use a private kubeconfig, so nothing else that
# switches the global kubectl context meanwhile can redirect these commands.
KCFG="$(mktemp)"; trap 'rm -f "$KCFG"' EXIT
kubectl config view --minify --flatten --context "kind-astro-ats-014-playground-060-02" > "$KCFG"
export KUBECONFIG="$KCFG"

ISTIO_VERSION="${ISTIO_VERSION:-1.30.5}"
REPO="https://istio-release.storage.googleapis.com/charts"
# First run pulls images; give Helm time to wait for ready pods.
WAIT=(--wait --timeout 10m)

echo "==> Istio $ISTIO_VERSION: base (CRDs)"
helm upgrade --install istio-base base --repo "$REPO" --version "$ISTIO_VERSION" \
  -n istio-system --create-namespace "${WAIT[@]}"

echo "==> Istio $ISTIO_VERSION: istiod"
helm upgrade --install istiod istiod --repo "$REPO" --version "$ISTIO_VERSION" \
  -n istio-system "${WAIT[@]}"

echo "==> Istio $ISTIO_VERSION: ingress gateway"
# ClusterIP: kind has no load balancer; astrona port-forwards it (config.yaml).
helm upgrade --install istio-ingressgateway gateway --repo "$REPO" --version "$ISTIO_VERSION" \
  -n istio-system --set service.type=ClusterIP "${WAIT[@]}"

echo "==> Waiting until the Istio CRDs are registered"
kubectl wait --for=condition=Established crd --all --timeout=120s >/dev/null

kubectl get pods -n istio-system
echo "==> Istio ready"
