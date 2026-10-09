#!/usr/bin/env bash
# Deploy what the 080-02 playground needs (runs after install-istio.sh):
#   - namespace starfleet (sidecar injection) + mesh-wide access logs
#   - shuttle, the test client every request is sent from
#   - namespace outpost (no sidecars): a partner server that only accepts
#     HTTPS with a client certificate signed by its own certificate authority
#   - the partner's client certificate, handed over as the Secret
#     partner-client-cert in namespace starfleet
# No ServiceEntry, Gateway, DestinationRule or VirtualService is created:
# writing them is the module. The mesh stays at its ALLOW_ANY default.
set -euo pipefail

# Pin this playground's cluster: use a private kubeconfig, so nothing else that
# switches the global kubectl context meanwhile can redirect these commands.
KCFG="$(mktemp)"; trap 'rm -f "$KCFG"' EXIT
kubectl config view --minify --flatten --context "kind-astro-ats-014-playground-080-02" > "$KCFG"
export KUBECONFIG="$KCFG"
cd "$(dirname "$0")"

echo "==> Namespace and access logs"
kubectl apply -f manifests/namespace.yaml -f manifests/access-logs.yaml

echo "==> Shuttle"
kubectl apply -f manifests/shuttle.yaml

echo "==> Certificates for the partner server in outpost"
# One certificate authority signs the partner's server certificate and your
# client certificate. The partner only answers clients that show a certificate
# from this authority.
CERTS="$(mktemp -d)"
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

echo "==> Partner server in namespace outpost"
kubectl apply -f manifests/outpost.yaml
kubectl -n outpost create secret generic partner-server-cert \
  --from-file=tls.crt="$CERTS/server.crt" --from-file=tls.key="$CERTS/server.key" \
  --from-file=ca.crt="$CERTS/ca.crt" --dry-run=client -o yaml | kubectl apply -f -

echo "==> The partner's client certificate, stored as a Secret in namespace starfleet"
kubectl -n starfleet create secret generic partner-client-cert \
  --from-file=tls.crt="$CERTS/client.crt" --from-file=tls.key="$CERTS/client.key" \
  --from-file=ca.crt="$CERTS/ca.crt" --dry-run=client -o yaml | kubectl apply -f -
rm -rf "$CERTS"

echo "==> Waiting for pods (first run pulls images, takes a few minutes)"
kubectl wait -n starfleet --for=condition=Available deploy --all --timeout=600s
kubectl wait -n outpost --for=condition=Available deploy --all --timeout=600s

kubectl get pods -n starfleet
kubectl get pods -n outpost
echo "==> Playground ats-014-playground-080-02 ready"
