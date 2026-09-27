#!/usr/bin/env bash
# egwtls-demo  : an injected client
# outside-mesh : a bare pod (no Service) running nginx that listens ONLY on
#                8443 with TLS and reports the scheme it was reached over.
set -euo pipefail

echo "[lab] Generating a self-signed certificate for partner.example.com..."
WORK="$(mktemp -d)"
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout "$WORK/tls.key" -out "$WORK/tls.crt" \
  -subj "/CN=partner.example.com/O=ica" \
  -addext "subjectAltName=DNS:partner.example.com" 2>/dev/null

kubectl create namespace outside-mesh --dry-run=client -o yaml | kubectl apply -f -
kubectl -n outside-mesh create secret tls partner-cert \
  --cert="$WORK/tls.crt" --key="$WORK/tls.key" --dry-run=client -o yaml | kubectl apply -f -
rm -rf "$WORK"

kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: egwtls-demo
  labels:
    istio-injection: enabled
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: partner-conf
  namespace: outside-mesh
data:
  default.conf: |
    server {
      listen 8443 ssl;
      server_name partner.example.com;
      ssl_certificate     /etc/nginx/certs/tls.crt;
      ssl_certificate_key /etc/nginx/certs/tls.key;
      location / {
        add_header Content-Type text/plain;
        return 200 "scheme=$scheme\n";
      }
    }
---
apiVersion: v1
kind: Pod
metadata:
  name: partner-api
  namespace: outside-mesh
  labels:
    app: partner-api
spec:
  containers:
    - name: nginx
      image: nginx:1.27-alpine
      ports:
        - containerPort: 8443
      volumeMounts:
        - name: conf
          mountPath: /etc/nginx/conf.d
        - name: certs
          mountPath: /etc/nginx/certs
          readOnly: true
  volumes:
    - name: conf
      configMap:
        name: partner-conf
    - name: certs
      secret:
        secretName: partner-cert
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: tester
  namespace: egwtls-demo
  labels:
    app: tester
spec:
  replicas: 1
  selector:
    matchLabels:
      app: tester
  template:
    metadata:
      labels:
        app: tester
    spec:
      containers:
        - name: tester
          image: curlimages/curl
          command: ["sh", "-c", "while true; do sleep 30; done"]
EOF

kubectl -n egwtls-demo rollout status deployment/tester --timeout=300s
kubectl -n outside-mesh wait --for=condition=Ready pod/partner-api --timeout=300s

PARTNER_IP=$(kubectl -n outside-mesh get pod partner-api -o jsonpath='{.status.podIP}')
printf '%s' "$PARTNER_IP" > /tmp/partner-ip

echo
echo "[lab] A TLS-ONLY endpoint exists outside the mesh registry:"
echo "[lab]   partner-api  ${PARTNER_IP}:8443  (TLS only; plaintext to 8443 fails)"
echo "[lab]   it answers with the scheme it was reached over, e.g. 'scheme=https'"
echo "[lab] The address is also in /tmp/partner-ip"
echo "[lab] The egress gateway is running and carrying nothing."
echo "[lab] No Istio configuration exists - that is the task."
