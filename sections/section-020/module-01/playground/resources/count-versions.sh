#!/usr/bin/env bash
# Sends N requests (default 20) from the shuttle pod to scout and counts which
# version answered. Extra arguments go to curl.
# Example: count-versions.sh 50 -H "end-user: jason"
count="${1:-20}"
if [ $# -gt 0 ]; then shift; fi
for _ in $(seq 1 "$count"); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s "$@" http://scout:9080/reviews/0 | grep -o 'scout-v[0-9]'
done | sort | uniq -c
