#!/usr/bin/env bash
# Reference solution for lab 000-01, applied by `astrona test` in CI.
#
# Two separate faults, two different fixes. Neither is reported by Kubernetes,
# because neither is an error - they are both "this pod was admitted without a
# proxy", which is a perfectly valid thing for a pod to be.
set -euo pipefail

# --- fault 1: legacy-app was never labelled for injection -------------------
# The label governs pods created FROM NOW ON, so the existing ones need a
# restart before anything changes.
kubectl label namespace legacy-app istio-injection=enabled --overwrite

# --- fault 2: reports opted out with an annotation --------------------------
# Patching the pod template triggers its own rollout.
kubectl -n mesh-demo patch deployment reports --type merge -p \
  '{"spec":{"template":{"metadata":{"annotations":{"sidecar.istio.io/inject":"true"}}}}}'

kubectl -n legacy-app rollout restart deployment

for ns in mesh-demo legacy-app; do
  for d in $(kubectl -n "$ns" get deployment -o name); do
    kubectl -n "$ns" rollout status "$d" --timeout=180s
  done
done

# let the new proxies register with the control plane before the grader looks
sleep 10
