#!/usr/bin/env bash
# Install Istio (sidecar mode) and the Gateway API CRDs into this playground's
# kind cluster:
#   Gateway API   the standard CRDs (Gateway, HTTPRoute, GatewayClass, ...).
#                 They are not part of Kubernetes and Istio does not ship them.
#   istio-system  istio-base (Istio CRDs) + istiod (control plane), with Helm
# No ingress gateway is installed: under the Gateway API, each Gateway object
# makes Istio build its own gateway Deployment and Service.
# Change the version with:  ISTIO_VERSION=<version> astrona run -c .
set -euo pipefail

ISTIO_VERSION="${ISTIO_VERSION:-1.30.5}"
# Must be a Gateway API release that this Istio version supports.
GATEWAY_API_VERSION="${GATEWAY_API_VERSION:-v1.3.0}"
REPO="https://istio-release.storage.googleapis.com/charts"
# First run pulls images; give Helm time to wait for ready pods.
WAIT=(--wait --timeout 10m)

echo "==> Gateway API CRDs ${GATEWAY_API_VERSION}"
kubectl get crd gateways.gateway.networking.k8s.io >/dev/null 2>&1 || \
  kubectl apply -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml"
kubectl wait --for=condition=Established --timeout=120s \
  crd/gateways.gateway.networking.k8s.io crd/httproutes.gateway.networking.k8s.io crd/gatewayclasses.gateway.networking.k8s.io

echo "==> Istio $ISTIO_VERSION: base (CRDs)"
helm upgrade --install istio-base base --repo "$REPO" --version "$ISTIO_VERSION" \
  -n istio-system --create-namespace "${WAIT[@]}"

echo "==> Istio $ISTIO_VERSION: istiod"
helm upgrade --install istiod istiod --repo "$REPO" --version "$ISTIO_VERSION" \
  -n istio-system "${WAIT[@]}"

echo "==> Waiting until the Istio CRDs are registered"
kubectl wait --for=condition=Established crd --all --timeout=120s >/dev/null

echo "==> Waiting for Istio to register its GatewayClass"
for _ in $(seq 1 60); do
  kubectl get gatewayclass istio >/dev/null 2>&1 && break
  sleep 2
done
kubectl get gatewayclass

kubectl get pods -n istio-system -l app=istiod
echo "==> Istio ready"
