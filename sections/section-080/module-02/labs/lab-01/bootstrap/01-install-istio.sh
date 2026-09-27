#!/usr/bin/env bash
# Puts istioctl 1.30.5 on the machine and installs a demo-profile control plane,
# which includes the istio-egressgateway this lab routes through.
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

echo "[lab] Installing the Istio control plane (demo profile)..."
istioctl install --set profile=demo -y
kubectl -n istio-system rollout status deployment/istiod --timeout=300s
kubectl -n istio-system rollout status deployment/istio-egressgateway --timeout=300s
echo "[lab] Control plane and egress gateway ready."
