#!/usr/bin/env bash
# Creates the planet `starfleet` (sidecar injection on), mesh-wide access logs
# and the shuttle client; the planet `outpost` (no sidecars) with the partner
# server, which only answers HTTPS callers that show a client certificate from
# its own certificate authority; and that client certificate, delivered as the
# Secret partner-client-cert in starfleet.
# astrona runs this script with KUBECONFIG pointed at the lab cluster.
set -euo pipefail
cd "$(dirname "$0")"

echo "==> Namespace, access logs and the shuttle"
kubectl apply -f manifests/namespace.yaml -f manifests/access-logs.yaml
kubectl apply -f manifests/shuttle.yaml

echo "==> Certificates for the partner outpost"
CERTS="$(mktemp -d)"; trap 'rm -rf "$CERTS"' EXIT
openssl req -x509 -newkey rsa:2048 -nodes -days 365 -subj "/CN=Outpost Root CA" \
  -keyout "$CERTS/ca.key" -out "$CERTS/ca.crt" 2>/dev/null
openssl req -newkey rsa:2048 -nodes -subj "/CN=partner.outpost.example" \
  -keyout "$CERTS/server.key" -out "$CERTS/server.csr" 2>/dev/null
printf 'subjectAltName=DNS:partner.outpost.example\n' > "$CERTS/server.ext"
openssl x509 -req -in "$CERTS/server.csr" -CA "$CERTS/ca.crt" -CAkey "$CERTS/ca.key" \
  -CAcreateserial -days 365 -extfile "$CERTS/server.ext" -out "$CERTS/server.crt" 2>/dev/null
openssl req -newkey rsa:2048 -nodes -subj "/CN=starfleet-departure-gate" \
  -keyout "$CERTS/client.key" -out "$CERTS/client.csr" 2>/dev/null
openssl x509 -req -in "$CERTS/client.csr" -CA "$CERTS/ca.crt" -CAkey "$CERTS/ca.key" \
  -CAcreateserial -days 365 -out "$CERTS/client.crt" 2>/dev/null

echo "==> Partner outpost"
kubectl apply -f manifests/outpost.yaml
kubectl -n outpost create secret generic partner-server-cert \
  --from-file=tls.crt="$CERTS/server.crt" --from-file=tls.key="$CERTS/server.key" \
  --from-file=ca.crt="$CERTS/ca.crt" --dry-run=client -o yaml | kubectl apply -f -

echo "==> The partner's client certificate, delivered to the planet starfleet"
kubectl -n starfleet create secret generic partner-client-cert \
  --from-file=tls.crt="$CERTS/client.crt" --from-file=tls.key="$CERTS/client.key" \
  --from-file=ca.crt="$CERTS/ca.crt" --dry-run=client -o yaml | kubectl apply -f -

echo "==> Waiting for pods (first run pulls images, takes a few minutes)"
kubectl wait -n starfleet --for=condition=Available deploy --all --timeout=600s
kubectl wait -n outpost --for=condition=Available deploy --all --timeout=600s
kubectl get pods -n starfleet
kubectl get pods -n outpost
