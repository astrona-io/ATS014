#!/usr/bin/env bash
# Labels the node as region local / zone zone-a, creates the namespace `starfleet`
# (sidecar injection on), mesh-wide access logs, the shuttle and the probe in two
# zones. astrona runs this script with KUBECONFIG pointed at the lab cluster.
# The lab starts with no DestinationRule: writing it is the task.
set -euo pipefail
cd "$(dirname "$0")"

echo "==> Labelling the node as region local, zone zone-a"
for n in $(kubectl get nodes -o name); do
  kubectl label "$n" topology.kubernetes.io/region=local --overwrite
  kubectl label "$n" topology.kubernetes.io/zone=zone-a --overwrite
done

echo "==> Namespace and access logs"
kubectl apply -f manifests/namespace.yaml -f manifests/access-logs.yaml

echo "==> The shuttle and the probe in two zones"
kubectl apply -f manifests/shuttle.yaml
kubectl apply -f manifests/probe-orbits.yaml

echo "==> Waiting for the shuttle and the two probes (first run pulls images, takes a few minutes)"
kubectl wait -n starfleet --for=condition=Available deploy/shuttle deploy/probe-zone-a deploy/probe-zone-b --timeout=600s
kubectl get pods -n starfleet
