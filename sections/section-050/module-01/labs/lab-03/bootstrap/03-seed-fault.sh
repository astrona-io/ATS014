#!/usr/bin/env bash
# The lab's starting state: somebody injected an abort fault on navcom and
# never scoped or removed it. Every request to navcom fails with 500, and
# because the scout VirtualService sends every request to scout v2 (which
# calls navcom), every scout response reports "Ratings service is currently
# unavailable". Scoping the fault to end-user: tester is the task.
set -euo pipefail
cd "$(dirname "$0")"

kubectl apply -f ../resources/starting-state.yaml
