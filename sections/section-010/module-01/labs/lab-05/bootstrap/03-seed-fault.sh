#!/usr/bin/env bash
# The lab's starting state: a correct DestinationRule and a correct
# VirtualService for the probe, but the probe Service's port is named `tcp`. Istio
# believes the name, treats the port as plain TCP, and never reads the
# VirtualService's `http` list - so the header rule does nothing and requests
# reach both versions. Declaring the port as HTTP again is the task.
set -euo pipefail
cd "$(dirname "$0")"

kubectl patch svc probe -n starfleet --type merge \
  -p '{"spec":{"ports":[{"name":"tcp","port":8000,"targetPort":8080}]}}'

kubectl apply -f ../resources/destinationrule-probe-and-virtualservice-probe.yaml

kubectl get svc probe -n starfleet -o jsonpath='{.spec.ports[0].name}{"\n"}'
