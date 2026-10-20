#!/usr/bin/env bash
# Sends 8 requests from the shuttle pod and counts which probe pod answered
# each one. Every argument goes to curl, so the last one is the URL.
# Example: count-pods.sh -H "x-user: alice" http://probe:8000/hostname
for _ in $(seq 1 8); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s "$@" | grep -o '"probe-[^"]*"'
done | sort | uniq -c
