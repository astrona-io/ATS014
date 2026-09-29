#!/usr/bin/env bash
# OS prep for the "How A Request Moves Through The Mesh" playground
# (`ats-014-playground-000-01`).
#
# Environment preparation only — there is no task and no grading. This script:
#   1. puts `istioctl` on the PATH,
#   2. installs the Istio control plane with the `demo` profile,
#   3. applies the starting workloads into `mesh-demo` and `mesh-legacy`,
#   4. makes sure every pod in `mesh-demo` really got a sidecar, and that
#      `mesh-legacy` deliberately did not.
#
# `mesh-legacy` is NOT injected on purpose. The 2/2 versus 1/1 contrast is what
# the module's first part is built on.
set -euo pipefail

ISTIO_VERSION="1.30.5"
NAMESPACE="mesh-demo"
PLAIN_NAMESPACE="mesh-legacy"

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
  echo "[playground] Downloading Istio ${ISTIO_VERSION}..."
  (cd "$WORK" && curl -fsSL https://istio.io/downloadIstio | ISTIO_VERSION="$ISTIO_VERSION" sh -)
  install -m 0755 "$WORK/istio-${ISTIO_VERSION}/bin/istioctl" "$BIN_DIR/istioctl"
fi
istioctl version --remote=false

echo "[playground] Installing the Istio control plane (demo profile)..."
istioctl install --set profile=demo -y
kubectl -n istio-system rollout status deployment/istiod --timeout=300s

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

for ns in "$NAMESPACE" "$PLAIN_NAMESPACE"; do
  kubectl get namespace "$ns" >/dev/null 2>&1 || {
    echo "[playground] ERROR: namespace $ns was never created." >&2
    exit 1
  }
done

# Every pod in the injected namespace must carry the istio-proxy sidecar.
# Restart anything that started before the webhook was in place.
echo "[playground] Ensuring every workload in $NAMESPACE has a sidecar..."
kubectl -n "$NAMESPACE" rollout restart deployment --all >/dev/null 2>&1 || true
for d in $(kubectl -n "$NAMESPACE" get deployment -o name); do
  kubectl -n "$NAMESPACE" rollout status "$d" --timeout=300s
done
for d in $(kubectl -n "$PLAIN_NAMESPACE" get deployment -o name); do
  kubectl -n "$PLAIN_NAMESPACE" rollout status "$d" --timeout=300s
done

echo "[playground] Ready."
echo "[playground] Injected namespace $NAMESPACE (expect 2/2):"
kubectl -n "$NAMESPACE" get pods -o wide
echo "[playground] Uninjected namespace $PLAIN_NAMESPACE (expect 1/1, on purpose):"
kubectl -n "$PLAIN_NAMESPACE" get pods -o wide
echo "[playground] No Istio traffic configuration has been created — this module is about the machinery underneath it."
