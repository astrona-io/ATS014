#!/usr/bin/env bash
# Sends 10 requests from the shuttle pod and counts which scout version answered.
# Every argument goes to curl, so the last one is the URL.
# Example: count-versions.sh -H "end-user: jason" http://scout:9080/reviews/0
for _ in $(seq 1 10); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s "$@" | grep -o 'scout-v[0-9]' || echo none
done | sort | uniq -c
