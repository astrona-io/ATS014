#!/usr/bin/env bash
# Sends N requests (default 5) from the shuttle pod to the probe and counts
# which version answered.
# Example: send-requests.sh 10
for _ in $(seq 1 "${1:-5}"); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s http://probe:8000/hostname | grep -o 'probe-v[0-9]'
done | sort | uniq -c
