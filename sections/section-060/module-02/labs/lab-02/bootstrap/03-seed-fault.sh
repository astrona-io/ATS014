#!/usr/bin/env bash
# The lab's starting state: an ingress class that no controller answers.
# The IngressClass `istio` names the controller "istio.io/ingress-controllers"
# (one letter too many), so istiod ignores every Ingress that claims it, and the
# ingress gateway never gets a listener for port 80. The Ingress itself is correct.
# Fixing the IngressClass is the task. spec.controller is immutable, so the fix
# is delete and create again.
set -euo pipefail
cd "$(dirname "$0")"

kubectl apply -f ../resources/ingressclass-istio.yaml

kubectl apply -f ../resources/ingress-starfleet.yaml
