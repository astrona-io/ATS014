#!/usr/bin/env bash
# The lab's starting state: a route out to the relay that never works.
#   - starfleet has a Sidecar "default" with REGISTRY_ONLY whose egress.hosts
#     list only ./* and istio-system/*
#   - the relay's ServiceEntry lives in the namespace "charts", which that
#     Sidecar does not take in, so the shuttle never sees it (fault 1)
#   - its port is declared TCP, so the VirtualService timeout in starfleet can
#     never apply, even once the entry is visible (fault 2)
# The Sidecar's REGISTRY_ONLY and the VirtualService are correct.
set -euo pipefail

RELAY_IP=$(kubectl -n outpost get pod relay -o jsonpath='{.status.podIP}')
[ -n "$RELAY_IP" ] || { echo "relay pod has no IP"; exit 1; }

kubectl apply -f - <<YAML
apiVersion: v1
kind: Namespace
metadata:
  name: charts
---
apiVersion: networking.istio.io/v1
kind: ServiceEntry
metadata:
  name: relay
  namespace: charts
spec:
  hosts:
  - relay.outpost.example
  addresses:
  - ${RELAY_IP}
  ports:
  - number: 8080
    name: tcp
    protocol: TCP
  location: MESH_EXTERNAL
  resolution: STATIC
  endpoints:
  - address: ${RELAY_IP}
YAML

kubectl apply -f - <<'YAML'
apiVersion: networking.istio.io/v1
kind: Sidecar
metadata:
  name: default
  namespace: starfleet
spec:
  outboundTrafficPolicy:
    mode: REGISTRY_ONLY
  egress:
  - hosts:
    - "./*"
    - "istio-system/*"
---
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: relay
  namespace: starfleet
spec:
  hosts:
  - relay.outpost.example
  http:
  - timeout: 2s
    route:
    - destination:
        host: relay.outpost.example
YAML

echo
echo "==> The relay is at ${RELAY_IP}:8080, the rogue at $(kubectl -n outpost get pod rogue -o jsonpath='{.status.podIP}'):8080"
echo "==> Lab ats-014-lab-070-01-02 ready"
