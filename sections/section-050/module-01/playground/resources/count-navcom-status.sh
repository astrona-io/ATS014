#!/usr/bin/env bash
# Sends 10 requests from the shuttle pod to navcom and counts the HTTP status codes.
# Example: count-navcom-status.sh
for _ in $(seq 1 10); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" http://navcom:9080/ratings/0
done | sort | uniq -c
