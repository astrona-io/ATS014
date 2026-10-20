#!/usr/bin/env bash
# The lab's starting state: DestinationRules with subsets for scout (v1, v2,
# v3) and navcom (v1), and a scout VirtualService that sends end-user: jason to
# scout v2, the version that calls navcom. No fault is injected yet: adding the
# two faults is the task.
set -euo pipefail
cd "$(dirname "$0")"

kubectl apply -f ../resources/starting-state.yaml
