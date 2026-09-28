#!/usr/bin/env bash
# Puts istioctl 1.30.5 on the machine and installs a demo-profile control plane,
# which includes the istio-egressgateway this lab routes through.
set -euo pipefail

ISTIO_VERSION="1.30.5"

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

echo "[lab] Installing the Istio control plane (demo profile)..."
# DNS capture makes a ServiceEntry host such as partner.example.com resolvable
# from inside a pod - the sidecar answers the lookup from the mesh registry.
# Without it the only way to reach the endpoint is by IP, and an IP authority
# matches no host-based gateway route.
istioctl install --set profile=demo \
  --set meshConfig.defaultConfig.proxyMetadata.ISTIO_META_DNS_CAPTURE=true -y
kubectl -n istio-system rollout status deployment/istiod --timeout=300s
kubectl -n istio-system rollout status deployment/istio-egressgateway --timeout=300s

# The demo profile publishes 80 and 443 on the egress gateway Service. This lab
# terminates the external port(s) 8080 on the gateway, and a mesh-side route to a
# port the Service does not publish resolves to a cluster that was never created
# - the call then fails with "503 NC cluster_not_found" and nothing explains why.
kubectl -n istio-system patch svc istio-egressgateway --type=json -p '[
  {"op":"add","path":"/spec/ports/-","value":{"name":"http-external-8080","port":8080,"targetPort":8080,"protocol":"TCP"}}
]'
echo "[lab] Control plane and egress gateway ready."
