#!/usr/bin/env bash
# The lab's starting state: a route through the egress gateway that is never
# used, and would be refused if it were.
#   - the ServiceEntry for relay.outpost.example and the DestinationRule with
#     the empty subset "relay" are correct
#   - the VirtualService lists only the gateway in its top-level gateways, so
#     the sidecars never get stage 1 and the shuttle calls the relay direct (fault 1)
#   - the Gateway names the gateway's own Service in servers[].hosts instead of
#     the external host, so the gateway has no route for the relay (fault 2)
set -euo pipefail

RELAY_IP=$(kubectl -n outpost get pod relay -o jsonpath='{.status.podIP}')
[ -n "$RELAY_IP" ] || { echo "relay pod has no IP"; exit 1; }

kubectl apply -f - <<YAML
apiVersion: networking.istio.io/v1
kind: ServiceEntry
metadata:
  name: relay
  namespace: starfleet
spec:
  hosts:
  - relay.outpost.example
  addresses:
  - ${RELAY_IP}
  ports:
  - number: 8080
    name: http
    protocol: HTTP
  location: MESH_EXTERNAL
  resolution: STATIC
  endpoints:
  - address: ${RELAY_IP}
YAML

kubectl apply -f - <<'YAML'
apiVersion: networking.istio.io/v1
kind: Gateway
metadata:
  name: departure-gate
  namespace: starfleet
spec:
  selector:
    istio: egress
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - istio-egress.istio-egress.svc.cluster.local
---
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: departure-gate-for-relay
  namespace: starfleet
spec:
  host: istio-egress.istio-egress.svc.cluster.local
  subsets:
  - name: relay
---
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: relay-via-departure-gate
  namespace: starfleet
spec:
  hosts:
  - relay.outpost.example
  gateways:
  - departure-gate
  http:
  - match:
    - gateways:
      - mesh
      port: 8080
    route:
    - destination:
        host: istio-egress.istio-egress.svc.cluster.local
        subset: relay
        port:
          number: 80
  - match:
    - gateways:
      - departure-gate
      port: 80
    route:
    - destination:
        host: relay.outpost.example
        port:
          number: 8080
YAML

echo
echo "==> The relay is at ${RELAY_IP}:8080 (relay.outpost.example)"
echo "==> Lab ats-014-lab-080-01-02 ready"
