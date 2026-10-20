#!/usr/bin/env bash
# Sends 15 requests from the shuttle pod to the probe and counts the HTTP status codes.
# Example: count-status.sh
for _ in $(seq 1 15); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" http://probe:8000/get
done | sort | uniq -c
