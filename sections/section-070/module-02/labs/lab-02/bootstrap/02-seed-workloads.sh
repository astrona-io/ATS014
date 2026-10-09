#!/usr/bin/env bash
# Creates the namespace `starfleet` (sidecar injection on) with mesh-wide access
# logs and the shuttle client, and the namespace `outpost` (no injection) with the
# vault: a TLS-only nginx pod with no Service, so it is not in the service registry.
# astrona runs this script with KUBECONFIG pointed at the lab cluster.
set -euo pipefail
cd "$(dirname "$0")"

echo "==> Namespace, access logs and the shuttle"
kubectl apply -f manifests/namespace.yaml -f manifests/access-logs.yaml
kubectl apply -f manifests/shuttle.yaml

echo "==> A self-signed certificate for vault.outpost.example"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout "$WORK/tls.key" -out "$WORK/tls.crt" \
  -subj "/CN=vault.outpost.example" \
  -addext "subjectAltName=DNS:vault.outpost.example" 2>/dev/null

echo "==> The outpost namespace and the vault pod"
kubectl create namespace outpost --dry-run=client -o yaml | kubectl apply -f -
kubectl -n outpost create secret tls vault-cert \
  --cert="$WORK/tls.crt" --key="$WORK/tls.key" --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f manifests/outpost.yaml

echo "==> Waiting for the pods (first run pulls images, takes a few minutes)"
kubectl wait -n starfleet --for=condition=Available deploy --all --timeout=600s
kubectl wait -n outpost --for=condition=Ready pod/vault --timeout=600s
kubectl get pods -n starfleet -o wide
kubectl get pods -n outpost -o wide
