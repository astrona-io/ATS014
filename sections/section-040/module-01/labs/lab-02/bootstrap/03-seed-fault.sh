#!/usr/bin/env bash
# The lab's starting state: someone tried to protect the scout's callers from a
# slow navcom by putting the timeout on the SAME route as the delay fault.
# A route with a fault ignores its own timeout, so jason's requests still take
# about 3 seconds. Moving the timeout to the caller's route (scout) is the task.
set -euo pipefail
cd "$(dirname "$0")"

kubectl apply -f ../resources/starting-state.yaml
