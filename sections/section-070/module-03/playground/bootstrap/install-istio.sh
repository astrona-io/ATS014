#!/usr/bin/env bash
# Install Istio (sidecar mode) into this playground's kind cluster with Helm:
#   istio-system   istio-base (CRDs) + istiod (control plane)
# No gateways: this playground only needs sidecars.
# Change the version with:  ISTIO_VERSION=1.29.3 astrona run -c .
set -euo pipefail

# Pin this playground's cluster: use a private kubeconfig, so nothing else that
# switches the global kubectl context meanwhile can redirect these commands.
KCFG="$(mktemp)"; trap 'rm -f "$KCFG"' EXIT
kubectl config view --minify --flatten --context "kind-astro-ats-014-playground-070-03" > "$KCFG"
export KUBECONFIG="$KCFG"

ISTIO_VERSION="${ISTIO_VERSION:-1.30.5}"
REPO="https://istio-release.storage.googleapis.com/charts"
# First run pulls images; give Helm time to wait for ready pods.
WAIT=(--wait --timeout 10m)

echo "==> Istio $ISTIO_VERSION: base (CRDs)"
helm upgrade --install istio-base base --repo "$REPO" --version "$ISTIO_VERSION" \
  -n istio-system --create-namespace "${WAIT[@]}"

# DNS capture: the sidecar answers name lookups from the mesh registry. A
# ServiceEntry host such as freighter.starfleet.mesh has no Kubernetes Service
# and no public DNS record, so without this the shuttle cannot resolve it.
echo "==> Istio $ISTIO_VERSION: istiod (with DNS capture)"
helm upgrade --install istiod istiod --repo "$REPO" --version "$ISTIO_VERSION" \
  -n istio-system "${WAIT[@]}" \
  --set-string meshConfig.defaultConfig.proxyMetadata.ISTIO_META_DNS_CAPTURE=true

echo "==> Waiting until the Istio CRDs are registered"
kubectl wait --for=condition=Established crd --all --timeout=120s >/dev/null

kubectl get pods -A -l 'app in (istiod,istio-ingress,istio-egress)'
echo "==> Istio ready"
