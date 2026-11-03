#!/usr/bin/env bash
# Sends N requests (default 20) from the shuttle pod to the probe and counts
# which zone answered.
# Example: count-zones.sh 40
for _ in $(seq 1 "${1:-20}"); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s http://probe:8000/hostname | grep -o 'probe-zone-[ab]' || echo failed
done | sort | uniq -c
