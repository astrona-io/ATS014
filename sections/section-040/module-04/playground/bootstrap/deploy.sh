#!/usr/bin/env bash
# Deploy what the 040-04 playground needs (runs after install-istio.sh):
#   - the node labelled region "local", zone "zone-a" (the shuttle's orbit)
#   - namespace starfleet (sidecar injection) + mesh-wide access logs
#   - shuttle (test client, locality local/zone-a from the node)
#   - the probe in two orbits (zone-a and zone-b) + a damaged zone-a probe at 0
# No DestinationRule is created: writing it is the module.
set -euo pipefail

# Pin this playground's cluster: use a private kubeconfig, so nothing else that
# switches the global kubectl context meanwhile can redirect these commands.
KCFG="$(mktemp)"; trap 'rm -f "$KCFG"' EXIT
kubectl config view --minify --flatten --context "kind-astro-ats-014-playground-040-04" > "$KCFG"
export KUBECONFIG="$KCFG"
cd "$(dirname "$0")"

echo "==> Labelling the node as region local, zone zone-a"
for n in $(kubectl get nodes -o name); do
  kubectl label "$n" topology.kubernetes.io/region=local --overwrite
  kubectl label "$n" topology.kubernetes.io/zone=zone-a --overwrite
done

echo "==> Namespace and access logs"
kubectl apply -f manifests/namespace.yaml -f manifests/access-logs.yaml

echo "==> Shuttle and the probe in two orbits"
kubectl apply -f manifests/shuttle.yaml
kubectl apply -f manifests/probe-orbits.yaml

echo "==> Waiting for pods (first run pulls images, takes a few minutes)"
kubectl wait -n starfleet --for=condition=Available deploy/shuttle deploy/probe-zone-a deploy/probe-zone-b --timeout=600s

kubectl get pods -n starfleet
echo "==> Playground ats-014-playground-040-04 ready"
