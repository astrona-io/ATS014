#!/usr/bin/env bash
# The lab's starting state: an ingress class that no controller answers.
# The IngressClass `istio` names the controller "istio.io/ingress-controllers"
# (one letter too many), so istiod ignores every Ingress that claims it, and the
# gate never gets orders for port 80. The Ingress itself is correct.
# Fixing the IngressClass is the task. spec.controller is immutable, so the fix
# is delete and create again.
set -euo pipefail

kubectl apply -f - <<'YAML'
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  name: istio
spec:
  controller: istio.io/ingress-controllers
YAML

kubectl apply -f - <<'YAML'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: starfleet
  namespace: starfleet
spec:
  ingressClassName: istio
  rules:
  - host: starfleet.example.com
    http:
      paths:
      - path: /anything
        pathType: Prefix
        backend:
          service:
            name: probe
            port:
              number: 8000
YAML
