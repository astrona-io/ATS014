#!/usr/bin/env bash
# Creates the namespace `starfleet` (sidecar injection on), mesh-wide access logs,
# the echo probe, the shuttle client and the archive (an nginx server that
# terminates TLS itself, with its own certificate for archive.starfleet.example.com
# in the secret archive-tls). It also leaves a self-signed certificate and key
# for starfleet.example.com in /tmp, for the learner to use.
# astrona runs this script with KUBECONFIG pointed at the lab cluster.
set -euo pipefail
cd "$(dirname "$0")"

echo "==> Namespace and access logs"
kubectl apply -f manifests/namespace.yaml -f manifests/access-logs.yaml

echo "==> Certificates"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /tmp/starfleet-example.key -out /tmp/starfleet-example.crt \
  -subj "/CN=starfleet.example.com/O=starfleet" 2>/dev/null
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout "$WORK/archive.key" -out "$WORK/archive.crt" \
  -subj "/CN=archive.starfleet.example.com/O=starfleet" 2>/dev/null
kubectl create secret tls archive-tls -n starfleet \
  --key="$WORK/archive.key" --cert="$WORK/archive.crt" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "==> The echo probe, the shuttle and the archive"
kubectl apply -f manifests/probe.yaml -f manifests/shuttle.yaml -f manifests/archive.yaml

echo "==> Waiting for the pods (first run pulls images, takes a few minutes)"
kubectl wait -n starfleet --for=condition=Available deploy --all --timeout=600s
kubectl get pods -n starfleet
echo "Certificate: /tmp/starfleet-example.crt"
echo "Private key: /tmp/starfleet-example.key"
