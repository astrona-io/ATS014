#!/usr/bin/env bash
# Deploy what playground ats-014-playground-060-03 needs (runs after install-istio.sh):
#   - planets starfleet and outpost (sidecar injection) + mesh-wide access logs
#   - the Starfleet in starfleet: bridge, cargo, scout v1-v3, navcom, shuttle
#   - the probe v1/v2 (echo service) in outpost
# No Gateway and no HTTPRoute are created: writing them is the module.
set -euo pipefail
cd "$(dirname "$0")"

echo "==> Planets and access logs"
kubectl apply -f manifests/namespace.yaml -f manifests/access-logs.yaml

echo "==> The Starfleet"
kubectl apply -n starfleet -f manifests/starfleet.yaml
kubectl apply -f manifests/shuttle.yaml

echo "==> The probe on planet outpost"
kubectl apply -f manifests/probe.yaml

echo "==> Waiting for pods (first run pulls images, takes a few minutes)"
kubectl wait -n starfleet --for=condition=Available deploy --all --timeout=600s
kubectl wait -n outpost --for=condition=Available deploy --all --timeout=600s

kubectl get pods -n starfleet
kubectl get pods -n outpost
echo "==> Playground ats-014-playground-060-03 ready"
