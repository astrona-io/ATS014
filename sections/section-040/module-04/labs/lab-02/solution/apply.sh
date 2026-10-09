#!/usr/bin/env bash
# Reference solution, applied only by `astrona test` (the `testing:` block).
# `astrona run` never runs this, so students still do the work themselves.
# Kept in step with solution.md - if one changes, change the other.
set -euo pipefail

kubectl -n starfleet patch deployment probe-zone-b --type merge \
  -p '{"spec":{"template":{"metadata":{"labels":{"istio-locality":"local.zone-b"}}}}}'
kubectl -n starfleet rollout status deployment probe-zone-b --timeout=300s

# Give istiod time to push the new endpoint locality to every proxy before the
# grader reads it back.
sleep 15
