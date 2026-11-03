#!/usr/bin/env bash
# Creates the namespace `starfleet` (sidecar injection on), mesh-wide access logs,
# the echo probe (v1 and v2 behind one Service on port 8000) and the shuttle client.
# It also leaves a self-signed certificate and key for probe.example.com in /tmp,
# for the learner to turn into a secret. No Gateway, no VirtualService and no
# secret exist: that is the task.
# astrona runs this script with KUBECONFIG pointed at the lab cluster.
set -euo pipefail
cd "$(dirname "$0")"

echo "==> Namespace and access logs"
kubectl apply -f manifests/namespace.yaml -f manifests/access-logs.yaml

echo "==> The echo probe and the shuttle"
kubectl apply -f manifests/probe.yaml -f manifests/shuttle.yaml

echo "==> Waiting for the pods (first run pulls images, takes a few minutes)"
kubectl wait -n starfleet --for=condition=Available deploy --all --timeout=600s
kubectl get pods -n starfleet

echo "==> Certificate and key for probe.example.com"
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /tmp/probe-example.key -out /tmp/probe-example.crt \
  -subj "/CN=probe.example.com/O=starfleet" 2>/dev/null
echo "Certificate: /tmp/probe-example.crt"
echo "Private key: /tmp/probe-example.key"
