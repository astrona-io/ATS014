#!/usr/bin/env bash
# Installs istioctl 1.30.5 and a demo-profile control plane with the mesh
# already switched to REGISTRY_ONLY, so unknown destinations are refused and a
# ServiceEntry is required rather than merely useful.
set -euo pipefail

ISTIO_VERSION="1.30.5"

BIN_DIR="/usr/local/bin"
[ -w "$BIN_DIR" ] || BIN_DIR="$HOME/.local/bin"
mkdir -p "$BIN_DIR"
export PATH="$BIN_DIR:$PATH"

if ! command -v istioctl >/dev/null 2>&1; then
  WORK="$(mktemp -d)"
  trap 'rm -rf "$WORK"' EXIT
  echo "[lab] Downloading Istio ${ISTIO_VERSION}..."
  (cd "$WORK" && curl -fsSL https://istio.io/downloadIstio | ISTIO_VERSION="$ISTIO_VERSION" sh -)
  install -m 0755 "$WORK/istio-${ISTIO_VERSION}/bin/istioctl" "$BIN_DIR/istioctl"
fi
istioctl version --remote=false

echo "[lab] Installing the Istio control plane (demo profile, REGISTRY_ONLY)..."
istioctl install --set profile=demo \
  --set meshConfig.outboundTrafficPolicy.mode=REGISTRY_ONLY -y
kubectl -n istio-system rollout status deployment/istiod --timeout=300s

echo "[lab] Mesh outbound policy:"
kubectl -n istio-system get cm istio -o jsonpath='{.data.mesh}' | grep -A2 outboundTrafficPolicy
