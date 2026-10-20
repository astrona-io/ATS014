#!/usr/bin/env bash
# The lab's starting state: an HTTPRoute with no Gateway to attach to.
# The HTTPRoute `bridge` names the Gateway `starfleet-gateway` in parentRefs,
# but no such Gateway exists, so the route has no status and no gateway proxy runs.
# Building the Gateway is the task - the HTTPRoute is correct.
set -euo pipefail
cd "$(dirname "$0")"

kubectl apply -f ../resources/httproute-bridge.yaml
echo "==> Lab ats-014-lab-060-03-02 ready"
