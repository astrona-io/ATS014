#!/usr/bin/env bash
# The lab's starting state: the connection pool on the probe is fine, but the
# VirtualService's retry policy retries every 5xx up to 5 times. A probe that
# answers 503 then receives each failing request 6 times. Stopping that retry
# storm is the task.
set -euo pipefail
cd "$(dirname "$0")"

kubectl apply -f ../resources/destinationrule-probe.yaml

kubectl apply -f ../resources/virtualservice-probe.yaml
echo "==> Starting state applied: the probe's VirtualService retries every 5xx five times"
