#!/usr/bin/env bash
# integrations : an injected client, plus an uninjected stand-in VM and its
#                ServiceAccount (this one is YOURS, so it belongs in the mesh)
# outside-mesh : a TLS-only partner API, and a third endpoint that must stay
#                blocked. No Services anywhere, so nothing is in the registry.
set -euo pipefail


# The stand-in "VMs" are ordinary pods with no sidecar, so they speak plain
# HTTP. A mesh-internal ServiceEntry makes callers attempt mTLS, which fails
# against a plaintext listener with "WRONG_VERSION_NUMBER" and a 503. A real
# onboarded VM runs a sidecar and needs none of this; the stand-in cannot, so
# the environment turns mTLS off for that host. It is not part of the task.
kubectl apply -f - <<'EOF'
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: legacy-plaintext
  namespace: integrations
spec:
  host: legacy.integrations.svc
  trafficPolicy:
    tls:
      mode: DISABLE
EOF
echo "[capstone] Generating a self-signed certificate for partner.example.com..."
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
  name: integrations
  labels:
    istio-injection: enabled
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: legacy-sa
  namespace: integrations
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
apiVersion: v1
kind: Pod
metadata:
  name: blocked-api
  namespace: outside-mesh
  labels:
    app: blocked-api
spec:
  containers:
    - name: app
      image: mccutchen/go-httpbin:v2.15.0
      command: ["/bin/go-httpbin", "-port", "8080"]
      ports:
        - containerPort: 8080
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: tester
  namespace: integrations
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
---
apiVersion: v1
kind: Pod
metadata:
  name: legacy-vm
  namespace: integrations
  labels:
    role: standin-vm
    sidecar.istio.io/inject: "false"
spec:
  serviceAccountName: legacy-sa
  containers:
    - name: app
      image: mccutchen/go-httpbin:v2.15.0
      command: ["/bin/go-httpbin", "-port", "8080"]
      ports:
        - containerPort: 8080
EOF

kubectl -n integrations rollout status deployment/tester --timeout=300s
kubectl -n integrations wait --for=condition=Ready pod/legacy-vm   --timeout=300s
kubectl -n outside-mesh wait --for=condition=Ready pod/partner-api --timeout=300s
kubectl -n outside-mesh wait --for=condition=Ready pod/blocked-api --timeout=300s

PARTNER=$(kubectl -n outside-mesh get pod partner-api -o jsonpath='{.status.podIP}')
BLOCKED=$(kubectl -n outside-mesh get pod blocked-api -o jsonpath='{.status.podIP}')
VM=$(kubectl -n integrations get pod legacy-vm -o jsonpath='{.status.podIP}')
printf '%s' "$PARTNER" > /tmp/partner-ip
printf '%s' "$BLOCKED" > /tmp/blocked-ip
printf '%s' "$VM"      > /tmp/vm-ip

echo
echo "[capstone] The mesh is REGISTRY_ONLY. Three endpoints, none registered:"
echo "[capstone]   partner-api ${PARTNER}:8443  TLS ONLY, reports the scheme it was reached over"
echo "[capstone]   legacy-vm   ${VM}:8080       YOUR machine, uninjected, runs as legacy-sa"
echo "[capstone]   blocked-api ${BLOCKED}:8080  must stay refused"
echo "[capstone] Addresses are in /tmp/partner-ip, /tmp/vm-ip and /tmp/blocked-ip"
echo "[capstone] No Istio configuration exists - that is the task."
