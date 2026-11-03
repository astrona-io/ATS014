#!/usr/bin/env bash
# Sends 8 requests from the shuttle pod and counts the HTTP status codes.
# Every argument goes to curl, so the last one is the URL.
# Example: status-codes.sh -H "x-canary: true" http://probe:8000/hostname
# The code 000 means curl got no HTTP response (for example a reset connection).
for _ in $(seq 1 8); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w '%{http_code}\n' --max-time 5 "$@" || true
done | sort | uniq -c
