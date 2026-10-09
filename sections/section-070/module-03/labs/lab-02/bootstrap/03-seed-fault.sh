#!/usr/bin/env bash
# The lab's starting state: a freighter beacon broken in three places.
#   1. The ServiceEntry's workloadSelector asks for app=freighters, a label no
#      WorkloadEntry carries, so the host has zero endpoints (503 UH).
#   2. WorkloadEntry freighter-vm-2 carries app=freigther (two letters swapped),
#      so even with the selector fixed, only freighter-vm-1 answers.
#   3. The ServiceEntry says MESH_EXTERNAL. Signals work with it, but it treats
#      the fleet's own machines as strangers. The task demands MESH_INTERNAL.
# The DestinationRule (tls DISABLE) is part of the environment, not a fault:
# the stand-ins have no sidecar and cannot answer mutual TLS.
set -euo pipefail

FREIGHTER_VM_1=$(kubectl get pod -n starfleet -l ship=freighter-vm-1 -o jsonpath='{.items[0].status.podIP}')
FREIGHTER_VM_2=$(kubectl get pod -n starfleet -l ship=freighter-vm-2 -o jsonpath='{.items[0].status.podIP}')
[ -n "$FREIGHTER_VM_1" ] && [ -n "$FREIGHTER_VM_2" ] || { echo "freighter pods have no address yet" >&2; exit 1; }

kubectl apply -f - <<YAML
apiVersion: networking.istio.io/v1
kind: WorkloadEntry
metadata:
  name: freighter-vm-1
  namespace: starfleet
spec:
  address: ${FREIGHTER_VM_1}
  labels:
    app: freighter
  serviceAccount: freighter
---
apiVersion: networking.istio.io/v1
kind: WorkloadEntry
metadata:
  name: freighter-vm-2
  namespace: starfleet
spec:
  address: ${FREIGHTER_VM_2}
  labels:
    app: freigther
  serviceAccount: freighter
YAML

kubectl apply -f - <<'YAML'
apiVersion: networking.istio.io/v1
kind: ServiceEntry
metadata:
  name: freighter
  namespace: starfleet
spec:
  hosts:
  - freighter.starfleet.mesh
  location: MESH_EXTERNAL
  resolution: STATIC
  ports:
  - number: 8080
    name: http
    protocol: HTTP
  workloadSelector:
    labels:
      app: freighters
---
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: freighter
  namespace: starfleet
spec:
  host: freighter.starfleet.mesh
  trafficPolicy:
    tls:
      mode: DISABLE
YAML
echo "==> Lab ats-014-lab-070-03-02 ready"
