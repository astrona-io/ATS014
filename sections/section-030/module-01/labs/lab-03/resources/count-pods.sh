#!/usr/bin/env bash
# Sends requests from the shuttle pod to the probe Service and counts which
# probe pod answered each one. Default: 8 requests. Example: count-pods.sh 16
set -euo pipefail

REQUESTS="${1:-8}"
for _ in $(seq 1 "$REQUESTS"); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s http://probe:8000/hostname | grep -o '"probe-[^"]*"'
done | sort | uniq -c
