#!/usr/bin/env bash
# The lab's starting state: TLS origination to the vault, with two mistakes.
#   - The VirtualService matches port 80, but the shuttle calls port 8080, so
#     the signal is never moved to 8443.
#   - The DestinationRule seals port 8080 instead of 8443: the proxy speaks
#     TLS to the plain port and plain HTTP to the TLS port.
# The ServiceEntry is correct. Fixing the other two is the task.
# astrona runs this script with KUBECONFIG pointed at the lab cluster.
set -euo pipefail

VAULT_IP=$(kubectl -n outpost get pod vault -o jsonpath='{.status.podIP}')
[[ -n "$VAULT_IP" ]] || { echo "vault pod has no IP"; exit 1; }

kubectl apply -f - <<YAML
apiVersion: networking.istio.io/v1
kind: ServiceEntry
metadata:
  name: vault
  namespace: starfleet
spec:
  hosts:
  - vault.outpost.example
  addresses:
  - ${VAULT_IP}
  location: MESH_EXTERNAL
  resolution: STATIC
  endpoints:
  - address: ${VAULT_IP}
  ports:
  - number: 8080
    name: http
    protocol: HTTP
  - number: 8443
    name: https
    protocol: HTTPS
YAML

kubectl apply -f - <<'YAML'
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: vault
  namespace: starfleet
spec:
  hosts:
  - vault.outpost.example
  http:
  - match:
    - port: 80
    route:
    - destination:
        host: vault.outpost.example
        port:
          number: 8443
YAML

kubectl apply -f - <<'YAML'
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: vault
  namespace: starfleet
spec:
  host: vault.outpost.example
  trafficPolicy:
    portLevelSettings:
    - port:
        number: 8080
      tls:
        mode: SIMPLE
        sni: vault.outpost.example
        insecureSkipVerify: true
YAML

echo "==> The vault is at ${VAULT_IP}. The shuttle calls http://${VAULT_IP}:8080/"
