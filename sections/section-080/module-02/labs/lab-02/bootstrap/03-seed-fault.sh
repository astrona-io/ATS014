#!/usr/bin/env bash
# The lab's starting state: the partner route through the egress gateway,
# with MUTUAL origination at the gateway, and two faults:
#   - stage 2 of the VirtualService sends the request to port 80 of the partner,
#     where nothing listens, so the TLS settings for 443 are never used (fault 1)
#   - the client certificate Secret only exists in starfleet; credentialName is
#     read from the gateway's own namespace, istio-egress (fault 2)
# The ServiceEntry, the Gateway, the gateway's DestinationRule and the MUTUAL
# DestinationRule are correct.
set -euo pipefail

kubectl apply -f - <<'YAML'
apiVersion: networking.istio.io/v1
kind: ServiceEntry
metadata:
  name: partner
  namespace: starfleet
spec:
  hosts:
  - partner.outpost.example
  ports:
  - number: 80
    name: http
    protocol: HTTP
  - number: 443
    name: https
    protocol: HTTPS
  location: MESH_EXTERNAL
  resolution: DNS
  endpoints:
  - address: partner.outpost.svc.cluster.local
---
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
    - partner.outpost.example
---
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: departure-gate
  namespace: starfleet
spec:
  host: istio-egress.istio-egress.svc.cluster.local
  subsets:
  - name: partner
---
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: partner-via-gate
  namespace: starfleet
spec:
  hosts:
  - partner.outpost.example
  gateways:
  - mesh
  - departure-gate
  http:
  - match:
    - gateways:
      - mesh
      port: 80
    route:
    - destination:
        host: istio-egress.istio-egress.svc.cluster.local
        subset: partner
        port:
          number: 80
  - match:
    - gateways:
      - departure-gate
      port: 80
    route:
    - destination:
        host: partner.outpost.example
        port:
          number: 80
---
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: partner-tls
  namespace: starfleet
spec:
  host: partner.outpost.example
  exportTo:
  - istio-egress
  trafficPolicy:
    portLevelSettings:
    - port:
        number: 443
      tls:
        mode: MUTUAL
        credentialName: partner-client-cert
        sni: partner.outpost.example
YAML

echo
echo "==> Starting state applied: requests to partner.outpost.example do not get through yet"
