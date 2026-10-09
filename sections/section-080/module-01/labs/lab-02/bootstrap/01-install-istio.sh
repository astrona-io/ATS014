#!/usr/bin/env bash
# Installs Istio 1.30.5 (sidecar mode) into the lab cluster with Helm:
#   istio-system   istio-base (CRDs) + istiod (control plane)
#   istio-egress   the egress gateway, pod label istio=egress
# astrona runs this script with KUBECONFIG pointed at the lab cluster.
set -euo pipefail

ISTIO_VERSION="${ISTIO_VERSION:-1.30.5}"
REPO="https://istio-release.storage.googleapis.com/charts"
# First run pulls images; give Helm time to wait for ready pods.
WAIT=(--wait --timeout 10m)

echo "==> Istio $ISTIO_VERSION: base (CRDs)"
helm upgrade --install istio-base base --repo "$REPO" --version "$ISTIO_VERSION" \
  -n istio-system --create-namespace "${WAIT[@]}"

# DNS capture lets a pod look up a ServiceEntry host such as
# relay.outpost.example: the sidecar answers from the mesh registry. Without it
# the shuttle could only call the relay by its IP, and the egress gateway routes
# by host name.
echo "==> Istio $ISTIO_VERSION: istiod (with DNS capture)"
helm upgrade --install istiod istiod --repo "$REPO" --version "$ISTIO_VERSION" \
  -n istio-system \
  --set-string meshConfig.defaultConfig.proxyMetadata.ISTIO_META_DNS_CAPTURE=true \
  "${WAIT[@]}"

echo "==> Istio $ISTIO_VERSION: egress gateway"
helm upgrade --install istio-egress gateway --repo "$REPO" --version "$ISTIO_VERSION" \
  -n istio-egress --create-namespace --set service.type=ClusterIP "${WAIT[@]}"

echo "==> Waiting until the Istio CRDs are registered"
kubectl wait --for=condition=Established crd --all --timeout=120s >/dev/null
echo "==> Istio ready"
