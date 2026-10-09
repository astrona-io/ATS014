#!/usr/bin/env bash
# The lab's starting state: a DestinationRule with subsets for all three scout
# versions, a VirtualService that sends every request to v1, and the patrol
# client pod that keeps sending requests for the whole lab.
# The rules are applied in the safe order (subsets first, then the route), and
# the patrol starts only after both have reached the proxies, so its access log
# starts clean.
set -euo pipefail
cd "$(dirname "$0")"

kubectl apply -f - <<'YAML'
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: scout
  namespace: starfleet
spec:
  host: scout
  subsets:
  - name: v1
    labels:
      version: v1
  - name: v2
    labels:
      version: v2
  - name: v3
    labels:
      version: v3
YAML
sleep 10

kubectl apply -f - <<'YAML'
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: scout
  namespace: starfleet
spec:
  hosts:
  - scout
  http:
  - route:
    - destination:
        host: scout
        subset: v1
YAML
sleep 10

echo "==> The patrol"
kubectl apply -f manifests/patrol.yaml
kubectl wait -n starfleet --for=condition=Available deploy/patrol --timeout=300s
echo "==> Lab ats-014-lab-010-03-01 ready"
