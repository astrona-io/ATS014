#!/usr/bin/env bash
# edge-egress  : two injected clients with different labels
# outside-mesh : plain-api (HTTP on 8080) and secure-api (TLS ONLY on 8443,
#                reports the scheme it was reached over). No Services.
set -euo pipefail

echo "[capstone] Generating a self-signed certificate for secure.partner.example..."
WORK="$(mktemp -d)"
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout "$WORK/tls.key" -out "$WORK/tls.crt" \
  -subj "/CN=secure.partner.example/O=ica" \
  -addext "subjectAltName=DNS:secure.partner.example" 2>/dev/null

kubectl create namespace outside-mesh --dry-run=client -o yaml | kubectl apply -f -
kubectl -n outside-mesh create secret tls secure-cert \
  --cert="$WORK/tls.crt" --key="$WORK/tls.key" --dry-run=client -o yaml | kubectl apply -f -
rm -rf "$WORK"

kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: edge-egress
  labels:
    istio-injection: enabled
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: secure-conf
  namespace: outside-mesh
data:
  default.conf: |
    server {
      listen 8443 ssl;
      server_name secure.partner.example;
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
  name: secure-api
  namespace: outside-mesh
  labels:
    app: secure-api
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
        name: secure-conf
    - name: certs
      secret:
        secretName: secure-cert
---
apiVersion: v1
kind: Pod
metadata:
  name: plain-api
  namespace: outside-mesh
  labels:
    app: plain-api
spec:
  containers:
    - name: app
      image: mccutchen/go-httpbin:v2.15.0
      args: ["-port", "8080"]
      ports:
        - containerPort: 8080
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: tester
  namespace: edge-egress
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
        egress-allowed: "true"
    spec:
      containers:
        - name: curl
          image: curlimages/curl
          command: ["sh", "-c", "while true; do sleep 30; done"]
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: other-client
  namespace: edge-egress
  labels:
    app: other-client
spec:
  replicas: 1
  selector:
    matchLabels:
      app: other-client
  template:
    metadata:
      labels:
        app: other-client
    spec:
      containers:
        - name: curl
          image: curlimages/curl
          command: ["sh", "-c", "while true; do sleep 30; done"]
EOF

kubectl -n edge-egress rollout status deployment/tester       --timeout=300s
kubectl -n edge-egress rollout status deployment/other-client --timeout=300s
kubectl -n outside-mesh wait --for=condition=Ready pod/plain-api  --timeout=300s
kubectl -n outside-mesh wait --for=condition=Ready pod/secure-api --timeout=300s

PLAIN=$(kubectl -n outside-mesh get pod plain-api  -o jsonpath='{.status.podIP}')
SECURE=$(kubectl -n outside-mesh get pod secure-api -o jsonpath='{.status.podIP}')
printf '%s' "$PLAIN"  > /tmp/plain-ip
printf '%s' "$SECURE" > /tmp/secure-ip

echo
echo "[capstone] Two endpoints outside the mesh registry:"
echo "[capstone]   plain-api   ${PLAIN}:8080   plain HTTP"
echo "[capstone]   secure-api  ${SECURE}:8443  TLS ONLY, reports the scheme it was reached over"
echo "[capstone] Addresses are in /tmp/plain-ip and /tmp/secure-ip"
echo "[capstone] Two clients: tester (egress-allowed=true) and other-client (no such label)"
echo "[capstone] No Istio configuration exists - that is the task."
