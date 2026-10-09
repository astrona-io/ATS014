#!/usr/bin/env bash
# Installs Istio 1.30.5 (sidecar mode) into the lab cluster with Helm:
#   istio-system   istio-base (CRDs) + istiod (control plane)
# astrona runs this script with KUBECONFIG pointed at the lab cluster.
set -euo pipefail

ISTIO_VERSION="${ISTIO_VERSION:-1.30.5}"
REPO="https://istio-release.storage.googleapis.com/charts"
# First run pulls images; give Helm time to wait for ready pods.
WAIT=(--wait --timeout 10m)

echo "==> Istio $ISTIO_VERSION: base (CRDs)"
helm upgrade --install istio-base base --repo "$REPO" --version "$ISTIO_VERSION" \
  -n istio-system --create-namespace "${WAIT[@]}"

# DNS capture: the sidecar answers name lookups from the mesh registry, so the
# ServiceEntry host freighter.starfleet.mesh resolves from the shuttle although
# no Kubernetes Service and no public DNS record exists for it.
echo "==> Istio $ISTIO_VERSION: istiod (with DNS capture)"
helm upgrade --install istiod istiod --repo "$REPO" --version "$ISTIO_VERSION" \
  -n istio-system "${WAIT[@]}" \
  --set-string meshConfig.defaultConfig.proxyMetadata.ISTIO_META_DNS_CAPTURE=true

echo "==> Waiting until the Istio CRDs are registered"
kubectl wait --for=condition=Established crd --all --timeout=120s >/dev/null
echo "==> Istio ready"
