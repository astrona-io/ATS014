#!/usr/bin/env bash
# Deploy what the 060-04 playground needs (runs after install-istio.sh):
#   - namespace starfleet (sidecar injection) + mesh-wide access logs
#   - the Starfleet: bridge, cargo, scout v1-v3, navcom (Bookinfo with space names)
#   - shuttle (test client) + probe v1/v2 (echo service)
#   - the archive: an nginx server that terminates TLS itself on port 8443, with
#     a self-signed certificate for archive.starfleet.example.com created here
# No Gateway, no VirtualService and no gateway TLS secret are created: writing
# them is the module.
set -euo pipefail

# Pin this playground's cluster: use a private kubeconfig, so nothing else that
# switches the global kubectl context meanwhile can redirect these commands.
KCFG="$(mktemp)"; WORK="$(mktemp -d)"; trap 'rm -rf "$KCFG" "$WORK"' EXIT
kubectl config view --minify --flatten --context "kind-astro-ats-014-playground-060-04" > "$KCFG"
export KUBECONFIG="$KCFG"
cd "$(dirname "$0")"

echo "==> Namespace and access logs"
kubectl apply -f manifests/namespace.yaml -f manifests/access-logs.yaml

echo "==> The Starfleet"
kubectl apply -n starfleet -f manifests/starfleet.yaml

echo "==> Shuttle and probe"
kubectl apply -f manifests/shuttle.yaml
kubectl apply -f manifests/probe.yaml

echo "==> The archive and its own certificate"
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout "$WORK/archive.key" -out "$WORK/archive.crt" \
  -subj "/CN=archive.starfleet.example.com/O=starfleet" 2>/dev/null
kubectl create secret tls archive-tls -n starfleet \
  --key="$WORK/archive.key" --cert="$WORK/archive.crt" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f manifests/archive.yaml

echo "==> Waiting for pods (first run pulls images, takes a few minutes)"
kubectl wait -n starfleet --for=condition=Available deploy --all --timeout=600s

kubectl get pods -n starfleet
echo "==> Playground ats-014-playground-060-04 ready"
