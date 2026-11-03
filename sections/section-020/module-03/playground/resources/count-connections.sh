#!/usr/bin/env bash
# Opens N separate connections (default 20) from the shuttle pod, one curl
# process per connection, and counts which probe version answered.
# A new curl process always opens a new connection.
# Usage: count-connections.sh [N] [host:port]     (default host:port is probe-tcp:8000)
count="${1:-20}"
target="${2:-probe-tcp:8000}"
kubectl exec -n starfleet deploy/shuttle -- sh -c \
  "for i in \$(seq 1 $count); do curl -s --max-time 5 http://$target/hostname; echo; done" \
  | grep -o 'probe-v[0-9]' | sort | uniq -c
