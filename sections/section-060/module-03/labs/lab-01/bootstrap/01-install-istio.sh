#!/usr/bin/env bash
# Installs istioctl 1.30.5, a demo-profile control plane, and the Gateway API
# CRDs. Gateway API is NOT part of core Kubernetes - without the CRDs every
# apply in this lab fails with `no matches for kind "Gateway"`, which looks
# like an Istio error and is not.
set -euo pipefail

ISTIO_VERSION="1.30.5"
# Must be a Gateway API release the installed Istio supports - check the Istio
# release notes before changing either version.
GATEWAY_API_VERSION="v1.3.0"

BIN_DIR="/usr/local/bin"
[ -w "$BIN_DIR" ] || BIN_DIR="$HOME/.local/bin"
mkdir -p "$BIN_DIR"
export PATH="$BIN_DIR:$PATH"

# Pin the version rather than accepting whatever istioctl happens to be on the
# machine: a different client installs a different control plane, and the whole
# course is written against ${ISTIO_VERSION}. BIN_DIR goes first on PATH above,
# so the pinned binary wins over any system-wide one.
have_version=""
command -v istioctl >/dev/null 2>&1 && \
  have_version=$(istioctl version --remote=false 2>/dev/null | awk '/client version/{print $3}')
if [ "$have_version" != "$ISTIO_VERSION" ]; then
  WORK="$(mktemp -d)"
  trap 'rm -rf "$WORK"' EXIT
  echo "[lab] Downloading Istio ${ISTIO_VERSION}..."
  (cd "$WORK" && curl -fsSL https://istio.io/downloadIstio | ISTIO_VERSION="$ISTIO_VERSION" sh -)
  install -m 0755 "$WORK/istio-${ISTIO_VERSION}/bin/istioctl" "$BIN_DIR/istioctl"
fi
istioctl version --remote=false

echo "[lab] Installing Gateway API CRDs (${GATEWAY_API_VERSION})..."
kubectl get crd gateways.gateway.networking.k8s.io >/dev/null 2>&1 || \
  kubectl apply -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml"
kubectl wait --for=condition=Established --timeout=120s \
  crd/gateways.gateway.networking.k8s.io crd/httproutes.gateway.networking.k8s.io

echo "[lab] Installing the Istio control plane (demo profile)..."
istioctl install --set profile=demo -y
kubectl -n istio-system rollout status deployment/istiod --timeout=300s

echo "[lab] Control plane ready. GatewayClass:"
kubectl get gatewayclass
