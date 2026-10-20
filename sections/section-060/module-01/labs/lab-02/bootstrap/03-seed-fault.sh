#!/usr/bin/env bash
# The lab's starting state: an ingress gateway with no listener.
# The Gateway selects istio=ingressgateway (the label of an istioctl install),
# but this Helm install labels its gateway pods istio=ingress. No pod gets the
# listener, so every request to the ingress gateway gets no reply (curl prints 000).
# Fixing the Gateway is the task - the VirtualService is correct.
set -euo pipefail
cd "$(dirname "$0")"

kubectl apply -f ../resources/gateway-starfleet-gateway.yaml

kubectl apply -f ../resources/virtualservice-bridge.yaml

kubectl get gateway,virtualservice -n starfleet
