#!/usr/bin/env bash
# Installs istioctl 1.30.5, a demo-profile control plane (with the ingress
# gateway) and the Gateway API CRDs, so all three ingress APIs are available.
set -euo pipefail

ISTIO_VERSION="1.30.5"
# Must be a Gateway API release the installed Istio supports.
GATEWAY_API_VERSION="v1.3.0"

BIN_DIR="/usr/local/bin"
[ -w "$BIN_DIR" ] || BIN_DIR="$HOME/.local/bin"
mkdir -p "$BIN_DIR"
export PATH="$BIN_DIR:$PATH"

if ! command -v istioctl >/dev/null 2>&1; then
  WORK="$(mktemp -d)"
  trap 'rm -rf "$WORK"' EXIT
  echo "[capstone] Downloading Istio ${ISTIO_VERSION}..."
  (cd "$WORK" && curl -fsSL https://istio.io/downloadIstio | ISTIO_VERSION="$ISTIO_VERSION" sh -)
  install -m 0755 "$WORK/istio-${ISTIO_VERSION}/bin/istioctl" "$BIN_DIR/istioctl"
fi
istioctl version --remote=false

echo "[capstone] Installing Gateway API CRDs (${GATEWAY_API_VERSION})..."
kubectl get crd gateways.gateway.networking.k8s.io >/dev/null 2>&1 || \
  kubectl apply -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml"
kubectl wait --for=condition=Established --timeout=120s \
  crd/gateways.gateway.networking.k8s.io crd/httproutes.gateway.networking.k8s.io

echo "[capstone] Installing the Istio control plane (demo profile)..."
istioctl install --set profile=demo -y
kubectl -n istio-system rollout status deployment/istiod --timeout=300s
kubectl -n istio-system rollout status deployment/istio-ingressgateway --timeout=300s

echo "[capstone] Ready. GatewayClass:"
kubectl get gatewayclass
