#!/usr/bin/env bash
# Creates the namespace `starfleet` (sidecar injection on), mesh-wide access logs,
# the Starfleet (bridge, cargo, scout v1-v3, navcom), the echo probe (v1 and v2)
# and the shuttle client. It also leaves a self-signed certificate and key for
# starfleet.example.com in /tmp. No Gateway, VirtualService, DestinationRule or
# secret exist: that is the task.
# astrona runs this script with KUBECONFIG pointed at the lab cluster.
set -euo pipefail
cd "$(dirname "$0")"

echo "==> Namespace and access logs"
kubectl apply -f manifests/namespace.yaml -f manifests/access-logs.yaml

echo "==> The Starfleet, the probe and the shuttle"
kubectl apply -n starfleet -f manifests/starfleet.yaml
kubectl apply -f manifests/probe.yaml -f manifests/shuttle.yaml

echo "==> Waiting for the pods (first run pulls images, takes a few minutes)"
kubectl wait -n starfleet --for=condition=Available deploy --all --timeout=600s
kubectl get pods -n starfleet

echo "==> Certificate and key for starfleet.example.com"
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /tmp/starfleet-edge.key -out /tmp/starfleet-edge.crt \
  -subj "/CN=starfleet.example.com/O=starfleet" 2>/dev/null
echo "Certificate: /tmp/starfleet-edge.crt"
echo "Private key: /tmp/starfleet-edge.key"
