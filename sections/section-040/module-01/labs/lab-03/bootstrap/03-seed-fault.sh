#!/usr/bin/env bash
# The lab's starting state: a retry policy that re-sends every 5xx, three
# times. It also re-sends the probe's own 500 errors, which are app bugs that
# fail the same way every time, so the probe gets four requests for every one.
# Narrowing the policy is the task.
set -euo pipefail
cd "$(dirname "$0")"

kubectl apply -f ../resources/virtualservice-probe.yaml
