#!/usr/bin/env bash
# The starting state: a third probe pod that answers every request with 503,
# behind the same `probe` Service, and no DestinationRule at all.
# astrona runs this script with KUBECONFIG pointed at the lab cluster.
set -euo pipefail
cd "$(dirname "$0")"

kubectl apply -f ../resources/deployment-probe-broken.yaml

kubectl rollout status -n starfleet deploy/probe-broken --timeout=300s
kubectl get pods -n starfleet -l app=probe
