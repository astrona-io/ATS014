#!/usr/bin/env bash
# OS prep for the "Ingress With The Kubernetes Gateway API" playground (`ats-014-playground-060-03`).
#
# Environment preparation only — there is no task and no grading. This script:
#   1. puts `istioctl` on the PATH,
#   2. installs the Istio control plane with the `demo` profile,
#   3. applies the module's starting workloads into namespace `gwapi-demo`,
#   4. makes sure every pod in that namespace really got a sidecar.
#
# The Istio objects the module is about (VirtualService, DestinationRule,
# Gateway, ServiceEntry, Sidecar, ...) are deliberately NOT created here.
# Creating them is the point of the module.
set -euo pipefail

ISTIO_VERSION="1.30.5"
NAMESPACE="gwapi-demo"

BIN_DIR="/usr/local/bin"
[ -w "$BIN_DIR" ] || BIN_DIR="$HOME/.local/bin"
mkdir -p "$BIN_DIR"
export PATH="$BIN_DIR:$PATH"

if ! command -v istioctl >/dev/null 2>&1; then
  WORK="$(mktemp -d)"
  trap 'rm -rf "$WORK"' EXIT
  echo "[playground] Downloading Istio ${ISTIO_VERSION}..."
  (cd "$WORK" && curl -fsSL https://istio.io/downloadIstio | ISTIO_VERSION="$ISTIO_VERSION" sh -)
  install -m 0755 "$WORK/istio-${ISTIO_VERSION}/bin/istioctl" "$BIN_DIR/istioctl"
fi
istioctl version --remote=false

echo "[playground] Installing the Istio control plane (demo profile)..."
istioctl install --set profile=demo -y
kubectl -n istio-system rollout status deployment/istiod --timeout=300s

# Gateway API is NOT part of core Kubernetes - the CRDs must be installed
# separately. The pin below must be a Gateway API release the installed Istio
# version supports; check the release notes for Istio ${ISTIO_VERSION} before
# changing either version.
GATEWAY_API_VERSION="v1.3.0"

echo "[playground] Installing Gateway API CRDs (${GATEWAY_API_VERSION})..."
kubectl get crd gateways.gateway.networking.k8s.io >/dev/null 2>&1 || \
  kubectl apply -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml"
kubectl wait --for=condition=Established --timeout=120s \
  crd/gateways.gateway.networking.k8s.io crd/httproutes.gateway.networking.k8s.io

# The lab manifest is also listed under bootstrap.manifests in config.yaml, so
# it may already be applied by the time this runs. kubectl apply is idempotent,
# and the rollout restart below covers the case where the pods were created
# before the injection webhook existed.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST=""
for candidate in \
  "$SCRIPT_DIR/../manifests/lab-start.yaml" \
  "./manifests/lab-start.yaml" \
  "$SCRIPT_DIR/manifests/lab-start.yaml"; do
  [ -f "$candidate" ] && { MANIFEST="$candidate"; break; }
done
if [ -n "$MANIFEST" ]; then
  echo "[playground] Applying starting workloads from $MANIFEST..."
  kubectl apply -f "$MANIFEST"
fi

kubectl get namespace "$NAMESPACE" >/dev/null 2>&1 || {
  echo "[playground] ERROR: namespace $NAMESPACE was never created." >&2
  exit 1
}

# Every pod must carry the istio-proxy sidecar. Restart anything that started
# before the webhook was in place, then wait for the namespace to settle.
echo "[playground] Ensuring every workload in $NAMESPACE has a sidecar..."
kubectl -n "$NAMESPACE" rollout restart deployment --all >/dev/null 2>&1 || true
for d in $(kubectl -n "$NAMESPACE" get deployment -o name); do
  kubectl -n "$NAMESPACE" rollout status "$d" --timeout=300s
done

echo "[playground] Ready. Namespace $NAMESPACE:"
kubectl -n "$NAMESPACE" get pods -o wide
echo "[playground] No Istio traffic configuration has been created — that is the module's subject."
