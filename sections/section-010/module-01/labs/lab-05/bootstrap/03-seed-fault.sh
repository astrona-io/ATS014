#!/usr/bin/env bash
# The lab's starting state: a correct DestinationRule and a correct
# VirtualService for the probe, but the probe Service's port is named `tcp`. Istio
# believes the name, treats the port as plain TCP, and never reads the
# VirtualService's `http` list - so the header rule does nothing and requests
# reach both versions. Declaring the port as HTTP again is the task.
set -euo pipefail

kubectl patch svc probe -n starfleet --type merge \
  -p '{"spec":{"ports":[{"name":"tcp","port":8000,"targetPort":8080}]}}'

kubectl apply -f - <<'YAML'
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: probe
  namespace: starfleet
spec:
  host: probe
  subsets:
  - name: v1
    labels:
      version: v1
  - name: v2
    labels:
      version: v2
---
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: probe
  namespace: starfleet
spec:
  hosts:
  - probe
  http:
  - match:
    - headers:
        x-mission:
          exact: test
    route:
    - destination:
        host: probe
        subset: v2
  - route:
    - destination:
        host: probe
        subset: v1
YAML

kubectl get svc probe -n starfleet -o jsonpath='{.spec.ports[0].name}{"\n"}'
